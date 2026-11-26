import Cocoa
import simd

struct TrackedWindow {
    let id: Int
    /// Global Cocoa coordinates (origin at bottom-left of the primary screen).
    let rect: CGRect
    /// Points per second, Cocoa orientation (y up).
    let velocity: SIMD2<Float>
}

/// Polls the window server for on-screen app windows. Only window positions are read,
/// never their contents, so no Screen Recording permission is needed.
final class WindowTracker {
    static let shared = WindowTracker()

    private(set) var windows: [TrackedWindow] = []   // front to back
    private(set) var generation = 0

    private var prev: [Int: CGRect] = [:]
    private var prevTime = CACurrentMediaTime()
    private var timers: [Timer] = []
    private let myPID = Int(getpid())

    // Dock estimate
    private var dockSlots: CGFloat = 12
    private var dockSeparators: CGFloat = 1
    private var dockTile: CGFloat = 0

    func start() {
        findDockPID()
        poll()
        refreshDock()
        let t = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in self?.poll() }
        let d = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refreshDock() }
        RunLoop.main.add(t, forMode: .common)
        RunLoop.main.add(d, forMode: .common)
        timers = [t, d]
    }

    func poll() {
        let now = CACurrentMediaTime()
        let dt = max(now - prevTime, 1.0 / 120.0)
        prevTime = now
        // Desktop elements are included so the Dock's own window can be seen (see `desktopAreas`).
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return }
        let primaryH = primary.frame.height

        var out: [TrackedWindow] = []
        var cur: [Int: CGRect] = [:]
        var desktops: [CGRect] = []
        for info in list {
            let layer = info[kCGWindowLayer as String] as? Int
            let pid = info[kCGWindowOwnerPID as String] as? Int
            if layer == dockLevel, pid == dockPID,
               let bd = info[kCGWindowBounds as String] as? NSDictionary,
               let r = CGRect(dictionaryRepresentation: bd as CFDictionary) {
                desktops.append(CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height))
                continue
            }
            guard layer == 0, pid != myPID else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            guard let id = info[kCGWindowNumber as String] as? Int,
                  let bd = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd as CFDictionary) else { continue }
            if r.width < 80 || r.height < 40 { continue }
            let rect = CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height)
            cur[id] = rect
            var vel = SIMD2<Float>(0, 0)
            if let p = prev[id] {
                vel = SIMD2(Float((rect.minX - p.minX) / dt), Float((rect.maxY - p.maxY) / dt))
            }
            out.append(TrackedWindow(id: id, rect: rect, velocity: vel))
        }
        prev = cur

        // The usable area of a screen changes when the Dock is resized or hidden.
        let areas = NSScreen.screens.map { $0.visibleFrame }
        let changed = out.count != windows.count
            || zip(out, windows).contains { $0.id != $1.id || $0.rect != $1.rect }
            || areas != screenAreas || desktops != desktopAreas
        if changed {
            windows = out
            screenAreas = areas
            desktopAreas = desktops
            generation &+= 1
        }
    }
    private var screenAreas: [CGRect] = []

    /// Screens (global Cocoa coordinates) showing a normal desktop Space, found by the Dock's
    /// screen-sized window. In a full-screen app's Space the Dock takes that window away.
    private(set) var desktopAreas: [CGRect] = []
    private let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
    private var dockPID = -1
    private func findDockPID() {
        dockPID = Int(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier ?? -1)
    }

    /// The Dock doesn't publish its frame, so estimate it from its preferences.
    func refreshDock() {
        findDockPID()   // the Dock gets a new process when it restarts
        let defs = UserDefaults(suiteName: "com.apple.dock")
        let tile = CGFloat(defs?.double(forKey: "tilesize") ?? 0)
        let apps = defs?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        let others = defs?.array(forKey: "persistent-others")?.count ?? 0
        let showRecents = defs?.object(forKey: "show-recents") as? Bool ?? true
        let recents = defs?.array(forKey: "recent-apps")?.count ?? 0

        var pinned = Set<String>()
        for a in apps {
            if let td = a["tile-data"] as? [String: Any], let bid = td["bundle-identifier"] as? String {
                pinned.insert(bid.lowercased())
            }
        }
        let running = NSWorkspace.shared.runningApplications.filter {
            guard $0.activationPolicy == .regular, let bid = $0.bundleIdentifier?.lowercased() else { return false }
            return !pinned.contains(bid) && bid != "com.apple.finder"
        }.count
        let extra = showRecents ? max(min(3, recents), running) : running

        let slots = CGFloat(2 + apps.count + others + extra) // + Finder + Trash
        let seps: CGFloat = (showRecents && extra > 0) ? 2 : 1
        if slots != dockSlots || seps != dockSeparators || tile != dockTile {
            dockSlots = slots
            dockSeparators = seps
            dockTile = tile
            generation &+= 1
        }
    }

    /// Estimated top surface of the Dock in screen-local coordinates, if the Dock sits at the bottom of this screen.
    /// Demo video only: fixed windows and Dock instead of the real ones.
    var dockOverride: CGRect?
    func inject(_ list: [TrackedWindow]) {
        let changed = list.count != windows.count
            || zip(list, windows).contains { $0.id != $1.id || $0.rect != $1.rect }
        if changed { windows = list; generation &+= 1 }
    }

    func dockRect(frame f: CGRect, visibleFrame vf: CGRect) -> CGRect? {
        if let d = dockOverride { return d }
        let h = vf.minY - f.minY
        guard h > 12 else { return nil }
        let tile = dockTile > 0 ? dockTile : max(16, h - 23)
        let width = min(f.width - 8, dockSlots * tile * 1.02 + dockSeparators * tile * 0.4 + tile * 0.5)
        return CGRect(x: (f.width - width) / 2, y: 0, width: width, height: h - 5)
    }
}
