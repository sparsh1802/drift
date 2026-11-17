import Cocoa

enum LoginItem {
    static let label = "local.drift.app"
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var enabled: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func set(_ on: Bool) {
        if on {
            let plist: NSDictionary = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
                "RunAtLoad": true,
            ]
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            plist.write(to: url, atomically: true)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var overlays: [Overlay] = []
    private var gpu: GPU!
    private var asleep = false
    private var rebuildPending = false
    private var nextSanta = Date().addingTimeInterval(Double.random(in: 300...900))
    private var santaTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let gpu = GPU.shared else {
            let alert = NSAlert()
            alert.messageText = "Drift couldn't start"
            alert.informativeText = "Metal graphics aren't available on this Mac."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        self.gpu = gpu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        WindowTracker.shared.start()
        Power.shared.start()
        rebuildOverlays()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        nc.addObserver(self, selector: #selector(applyAll), name: .driftSettingsChanged, object: nil)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(didSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(didSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        let st = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.santaTick() }
        RunLoop.main.add(st, forMode: .common)
        santaTimer = st

        if CommandLine.arguments.contains("--santa") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.sendSanta() }
        }
        if CommandLine.arguments.contains("--tree") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.plantTree() }
        }
        if CommandLine.arguments.contains("--snowman") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.buildSnowman() }
        }
    }

    // MARK: Overlays

    private func rebuildOverlays() {
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { Overlay(screen: $0, gpu: gpu) }
        applyAll()
    }

    @objc private func screensChanged() {
        guard !rebuildPending else { return }
        rebuildPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.rebuildPending = false
            self?.rebuildOverlays()
        }
    }

    @objc private func applyAll() {
        let s = Settings.shared
        for o in overlays {
            o.apply(paused: s.paused || asleep, behind: s.behindWindows, saving: Power.shared.saving)
        }
        updateIcon()
    }

    @objc private func didSleep() { asleep = true; applyAll() }
    @objc private func didWake() { asleep = false; applyAll() }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let img = Settings.shared.mode.image
        img?.isTemplate = true
        button.image = img
        button.appearsDisabled = Settings.shared.paused
        button.toolTip = "Drift — \(Settings.shared.mode.title)"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared

        let header = NSMenuItem(title: "Drift", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for m in Mode.allCases {
            let it = NSMenuItem(title: m.title, action: #selector(pickMode(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = m.rawValue
            it.state = m == s.mode ? .on : .off
            it.image = m.image
            menu.addItem(it)
        }

        menu.addItem(.separator())
        menu.addItem(sliderItem(title: "Intensity", value: s.intensity, min: 0.25, max: 2.0, action: #selector(intensityChanged(_:))))
        menu.addItem(sliderItem(title: "Wind  ←  →", value: s.wind, min: -1, max: 1, action: #selector(windChanged(_:))))

        menu.addItem(.separator())
        menu.addItem(toggle("Settle on Windows", s.pileOnWindows, #selector(togglePile)))
        menu.addItem(toggle("Settle on Dock", s.snowOnDock, #selector(toggleDock)))
        menu.addItem(toggle("Cursor Interaction", s.cursorInteraction, #selector(toggleCursor)))
        menu.addItem(toggle("Snowballs & Snowmen", s.snowplay, #selector(toggleSnowplay)))
        menu.addItem(toggle("Santa Visits", s.santaVisits, #selector(toggleSanta)))
        menu.addItem(toggle("Behind Windows", s.behindWindows, #selector(toggleBehind)))
        menu.addItem(toggle("Save Energy on Battery", s.batterySaver, #selector(toggleBattery)))

        menu.addItem(.separator())
        let build = NSMenuItem(title: "Build a Snowman", action: #selector(buildSnowman), keyEquivalent: "")
        build.target = self
        build.image = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: nil)
        menu.addItem(build)
        let tree = NSMenuItem(title: "Plant a Christmas Tree", action: #selector(plantTree), keyEquivalent: "")
        tree.target = self
        tree.image = NSImage(systemSymbolName: "tree", accessibilityDescription: nil)
        menu.addItem(tree)
        let clearTrees = NSMenuItem(title: "Remove Trees", action: #selector(removeTrees), keyEquivalent: "")
        clearTrees.target = self
        menu.addItem(clearTrees)
        let santa = NSMenuItem(title: "Send Santa", action: #selector(sendSanta), keyEquivalent: "")
        santa.target = self
        santa.image = NSImage(systemSymbolName: "gift", accessibilityDescription: nil)
        menu.addItem(santa)
        let shake = NSMenuItem(title: "Shake Everything Off", action: #selector(shakeOff), keyEquivalent: "")
        shake.target = self
        menu.addItem(shake)
        let pause = NSMenuItem(title: s.paused ? "Resume" : "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        menu.addItem(toggle("Open at Login", LoginItem.enabled, #selector(toggleLogin)))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Drift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func toggle(_ title: String, _ on: Bool, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        it.state = on ? .on : .off
        return it
    }

    private func sliderItem(title: String, value: Double, min: Double, max: Double, action: Selector) -> NSMenuItem {
        let item = NSMenuItem()
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 46))
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.menuFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 20, y: 25, width: 200, height: 17)
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        slider.frame = NSRect(x: 18, y: 3, width: 204, height: 22)
        slider.isContinuous = true
        slider.controlSize = .small
        v.addSubview(label)
        v.addSubview(slider)
        item.view = v
        return item
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = Mode(rawValue: raw) {
            if Settings.shared.paused { Settings.shared.paused = false }
            Settings.shared.mode = m
        }
    }
    @objc private func intensityChanged(_ sender: NSSlider) { Settings.shared.intensity = sender.doubleValue }
    @objc private func windChanged(_ sender: NSSlider) { Settings.shared.wind = sender.doubleValue }
    @objc private func togglePile() { Settings.shared.pileOnWindows.toggle() }
    @objc private func toggleDock() { Settings.shared.snowOnDock.toggle() }
    @objc private func toggleCursor() { Settings.shared.cursorInteraction.toggle() }
    @objc private func toggleBehind() { Settings.shared.behindWindows.toggle() }
    @objc private func toggleBattery() { Settings.shared.batterySaver.toggle(); Power.shared.refresh() }
    @objc private func togglePause() { Settings.shared.paused.toggle() }
    @objc private func toggleLogin() { LoginItem.set(!LoginItem.enabled) }
    @objc private func shakeOff() { overlays.forEach { $0.sim.shakeOff() } }
    @objc private func toggleSnowplay() { Settings.shared.snowplay.toggle() }
    @objc private func toggleSanta() { Settings.shared.santaVisits.toggle() }

    /// The overlay under the pointer first, then the rest.
    private var overlaysByPointer: [Overlay] {
        let mouse = NSEvent.mouseLocation
        return overlays.sorted { a, _ in a.screen.frame.contains(mouse) }
    }
    @objc private func plantTree() {
        if Settings.shared.paused { Settings.shared.paused = false }
        for o in overlaysByPointer where o.sim.plantTree() { return }
        NSSound.beep()
    }
    @objc private func removeTrees() { overlays.forEach { $0.sim.removeTrees() } }
    @objc private func sendSanta() {
        if Settings.shared.paused { Settings.shared.paused = false }
        // Santa rides along the Dock, so prefer the screen that has it.
        let target = overlays.first { $0.sim.dockLocal != nil && !$0.sim.fullscreenCovered }
            ?? overlaysByPointer.first { !$0.sim.fullscreenCovered }
        target?.sim.sendSanta()
    }
    private func santaTick() {
        guard Settings.shared.santaVisits, !Settings.shared.paused, !asleep, Date() >= nextSanta else { return }
        nextSanta = Date().addingTimeInterval(Double.random(in: 1800...3600))
        sendSanta()
    }
    @objc private func buildSnowman() {
        if Settings.shared.paused { Settings.shared.paused = false }
        let mouse = NSEvent.mouseLocation
        let ordered = overlays.sorted { a, _ in a.screen.frame.contains(mouse) }
        for o in ordered where o.sim.buildSnowman() { return }
        NSSound.beep()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
