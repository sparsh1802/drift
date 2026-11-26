import Cocoa
import MetalKit

/// Never becomes key or main, and clicking it doesn't bring Drift to the front.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The Metal view; forwards mouse presses on snow, snowballs, trees and Santa to the simulation.
final class OverlayView: MTKView {
    weak var sim: Simulation?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { sim?.mouseDown(at: local(e)); NSCursor.closedHand.set() }
    override func mouseDragged(with e: NSEvent) { sim?.mouseDragged(at: local(e)) }
    override func mouseUp(with e: NSEvent) { sim?.mouseUp(at: local(e)); NSCursor.openHand.set() }

    private func local(_ e: NSEvent) -> SIMD2<Float> {
        let p = convert(e.locationInWindow, from: nil)
        return SIMD2(Float(p.x), Float(p.y))
    }
}

/// A transparent window covering one screen that hosts the weather. It lets clicks
/// through everywhere except over the things you can play with.
final class Overlay {
    let screen: NSScreen
    let window: OverlayPanel
    let view: OverlayView
    let sim: Simulation
    let renderer: Renderer
    private var takingMouse = false
    private var shown = false

    init(screen: NSScreen, gpu: GPU) {
        self.screen = screen
        sim = Simulation(screen: screen)
        renderer = Renderer(gpu: gpu, sim: sim)

        window = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.setFrame(screen.frame, display: false)

        view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), device: gpu.device)
        view.sim = sim
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.sampleCount = GPU.sampleCount
        view.framebufferOnly = true
        view.autoresizingMask = [.width, .height]
        view.delegate = renderer
        window.contentView = view
        view.layer?.isOpaque = false

        renderer.afterUpdate = { [weak self] in self?.updateMouseCapture() }
    }

    /// Take the mouse only while the pointer is over snow or a toy, so the desktop's
    /// selection box (and every other click) still works everywhere else.
    private func updateMouseCapture() {
        let want = sim.wantsMouse()
        guard want != takingMouse else { return }
        takingMouse = want
        window.ignoresMouseEvents = !want
        if want { NSCursor.openHand.set() } else if !sim.isDragging { NSCursor.arrow.set() }
    }

    func apply(paused: Bool, behind: Bool, saving: Bool) {
        let level = behind
            ? Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
            : Int(CGWindowLevelForKey(.dockWindow)) + 1
        window.level = NSWindow.Level(rawValue: level)
        view.preferredFramesPerSecond = saving ? 30 : 60
        sim.saving = saving
        sim.settingsChanged()
        if paused {
            view.isPaused = true
            window.ignoresMouseEvents = true
            takingMouse = false
            window.orderOut(nil)
            shown = false
        } else if !shown {
            // Only when coming back: apply() also runs on every slider tick, and resetting the
            // clock each time would stall the weather while a slider is dragged.
            renderer.resetClock()
            window.orderFrontRegardless()
            view.isPaused = false
            shown = true
        }
    }

    func close() {
        view.isPaused = true
        view.delegate = nil
        window.orderOut(nil)
        window.close()
    }
}
