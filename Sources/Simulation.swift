import Cocoa
import simd

// MARK: - Basic types

enum PState { case falling, resting, spark }

enum Kind {
    static let snow: UInt8 = 0
    static let petal: UInt8 = 1
    static let leaf: UInt8 = 2
    static let rain: UInt8 = 3
    static let firefly: UInt8 = 4
    static let meteor: UInt8 = 5
    static let flash: UInt8 = 6
    static let spark: UInt8 = 7
}

struct Particle {
    var p = SIMD2<Float>(0, 0)
    var v = SIMD2<Float>(0, 0)
    var size: Float = 2
    var rot: Float = 0
    var spin: Float = 0
    var phase: Float = 0
    var depth: Float = 1
    var life: Float = 0        // spark: time left · resting: age
    var maxLife: Float = 1
    var delay: Float = 0
    var gravity: Float = 0
    var color = SIMD4<Float>(1, 1, 1, 1)
    var kind: UInt8 = 0
    var state: PState = .falling
    var transient = false      // not part of the steady population; removed when it leaves
    var ledgeKey = 0
    var offset: Float = 0
    var noClip = false         // draw even over app windows
}

@inline(__always) func rnd(_ a: Float, _ b: Float) -> Float { Float.random(in: a..<b) }

@inline(__always) func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: - Ledge (a surface snow can settle on: a window top, the Dock, the screen bottom)

final class Ledge {
    static let binW: Float = 3

    let key: Int
    var x0: Float
    var y: Float
    var width: Float
    let maxH: Float
    var heights: [Float]
    var caps: [Float]
    var lumps: [Float]
    var dirty = false
    var hidden = false
    var hiddenSince: Float = 0
    private var flip = false

    init(key: Int, x0: Float, y: Float, width: Float, maxH: Float) {
        self.key = key
        self.x0 = x0
        self.y = y
        self.width = width
        self.maxH = maxH
        let n = max(2, Int(width / Ledge.binW))
        heights = Array(repeating: 0, count: n)
        caps = Array(repeating: maxH, count: n)
        lumps = (0..<n).map { _ in rnd(-0.5, 0.5) }
    }

    func reset(x0: Float, y: Float, width: Float) {
        self.x0 = x0
        self.y = y
        self.width = width
        let n = max(2, Int(width / Ledge.binW))
        heights = Array(repeating: 0, count: n)
        caps = Array(repeating: maxH, count: n)
        lumps = (0..<n).map { _ in rnd(-0.5, 0.5) }
    }

    func resize(width: Float) {
        self.width = width
        let n = max(2, Int(width / Ledge.binW))
        if n > heights.count {
            let extra = n - heights.count
            heights += Array(repeating: 0, count: extra)
            caps += Array(repeating: maxH, count: extra)
            lumps += (0..<extra).map { _ in rnd(-0.5, 0.5) }
        } else if n < heights.count {
            let drop = heights.count - n
            heights.removeLast(drop)
            caps.removeLast(drop)
            lumps.removeLast(drop)
        }
    }

    @inline(__always) func bin(at x: Float) -> Int? {
        let f = (x - x0) / Ledge.binW
        if f < 0 { return nil }
        let i = Int(f)
        return i < heights.count ? i : nil
    }

    @inline(__always) func binX(_ i: Int) -> Float { x0 + (Float(i) + 0.5) * Ledge.binW }

    func deposit(_ i: Int, _ amount: Float) {
        let fill = 1 - 0.5 * heights[i] / maxH
        let a = amount * fill
        add(i, a * 0.5)
        if i > 0 { add(i - 1, a * 0.25) }
        if i < heights.count - 1 { add(i + 1, a * 0.25) }
        dirty = true
    }

    @inline(__always) private func add(_ i: Int, _ a: Float) {
        heights[i] = min(heights[i] + a, min(caps[i], maxH))
    }

    /// Let steep slopes slump so piles look like soft drifts.
    func relax() {
        guard dirty else { return }
        dirty = false
        let n = heights.count
        guard n > 1 else { return }
        let slope: Float = 1.3
        flip.toggle()
        for k in 0..<(n - 1) {
            let i = flip ? k : n - 2 - k
            let d = heights[i] - heights[i + 1]
            if d > slope + 0.01 {
                let t = (d - slope) * 0.5
                heights[i] -= t
                heights[i + 1] = min(heights[i + 1] + t, caps[i + 1])
                dirty = true
            } else if d < -slope - 0.01 {
                let t = (-d - slope) * 0.5
                heights[i + 1] -= t
                heights[i] = min(heights[i] + t, caps[i])
                dirty = true
            }
        }
    }

    func clearHeights() {
        for i in heights.indices { heights[i] = 0 }
    }

    var hasSnow: Bool { heights.contains { $0 > 0.3 } }
}

// MARK: - Simulation (one per screen)

final class Simulation {
    let frame: CGRect
    let visibleFrame: CGRect
    var size: SIMD2<Float>
    let origin: CGPoint
    var saving = false

    private(set) var time: Float = 0
    private(set) var mode: Mode
    var particles: [Particle] = []
    var ledges: [Int: Ledge] = [:]
    var ledgeList: [Ledge] = []
    let play = SnowplayState()
    /// Window rects (local, minX/minY/maxX/maxY) that hide snow — front-most first.
    var clipRects: [SIMD4<Float>] = []
    /// The Dock area (local), which sits in front of apps so snow there stays visible.
    var dockLocal: CGRect?
    /// A full-screen app owns this screen: draw nothing.
    var fullscreenCovered = false
    private var lastGeneration = -1

    var cursor = SIMD2<Float>(-99999, -99999)
    private var cursorPrev: SIMD2<Float>?
    var cursorVel = SIMD2<Float>(0, 0)
    var cursorStill: Float = 0

    private var wind: Float = 0
    private var flash: Float = 0
    private var nextLightning: Float = rnd(6, 15)
    private var secondFlashAt: Float = -1

    let maxParticles = 6000
    static let debugShowAll = CommandLine.arguments.contains("--show-all")

    convenience init(screen: NSScreen) {
        self.init(frame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        size = SIMD2(Float(frame.width), Float(frame.height))
        origin = frame.origin
        mode = Settings.shared.mode
        for _ in 0..<targetCount() { particles.append(spawn(initial: true)) }
    }

    // MARK: Settings

    func settingsChanged() {
        let m = Settings.shared.mode
        if m != mode { switchMode(to: m) }
        lastGeneration = -1   // force a ledge resync (toggles may have changed)
    }

    private func switchMode(to m: Mode) {
        mode = m
        // Old particles finish their fall and leave; the new weather fades in from the top.
        for i in particles.indices where !particles[i].transient {
            particles[i].transient = true
            if particles[i].kind == Kind.firefly {
                particles[i].state = .spark
                particles[i].life = 1.2
                particles[i].maxLife = 1.2
                particles[i].gravity = 0
            } else if particles[i].delay > 0 {
                particles[i].state = .spark
                particles[i].life = 0
            }
        }
        if m == .rain { nextLightning = time + rnd(6, 15) }
    }

    func targetCount() -> Int {
        let area = size.x * size.y / (1440 * 900)
        let base: Float
        switch mode {
        case .snow: base = 380
        case .rain: base = 420
        case .leaves: base = 45
        case .sakura: base = 90
        case .fireflies: base = 55
        case .starfall: base = 7
        }
        var n = base * area * Float(Settings.shared.intensity)
        if saving { n *= 0.5 }
        return max(1, Int(n))
    }

    // MARK: Spawning

    private func spawn(initial: Bool) -> Particle {
        var q = Particle()
        let w = size.x, h = size.y
        q.p = SIMD2(rnd(-0.1 * w, 1.1 * w) - wind * 2, initial ? rnd(0, h) : h + rnd(4, 60))
        q.phase = rnd(0, 6.283)
        switch mode {
        case .snow:
            q.kind = Kind.snow
            q.depth = pow(rnd(0, 1), 0.7)
            q.size = (1.0 + q.depth * 3.0) * rnd(0.8, 1.25)
            q.color = SIMD4(1, 1, 1, 0.35 + 0.6 * q.depth)
            q.v = SIMD2(0, -(25 + 70 * q.depth))
        case .rain:
            q.kind = Kind.rain
            q.depth = rnd(0, 1)
            q.size = 0.5 + q.depth * 0.7
            q.color = SIMD4(0.78, 0.85, 1.0, 0.18 + 0.4 * q.depth)
            q.v = SIMD2(wind * 1.6, -(700 + 500 * q.depth))
            if !initial { q.p.y = h + rnd(4, 220) }
        case .leaves:
            q.kind = Kind.leaf
            q.depth = rnd(0.55, 1)
            q.size = rnd(6, 10.5)
            let palette: [SIMD3<Float>] = [
                SIMD3(0.89, 0.45, 0.13), SIMD3(0.80, 0.22, 0.10), SIMD3(0.93, 0.67, 0.18),
                SIMD3(0.62, 0.33, 0.14), SIMD3(0.85, 0.55, 0.20), SIMD3(0.70, 0.18, 0.12),
            ]
            let c = palette.randomElement()!
            q.color = SIMD4(c.x, c.y, c.z, 0.96)
            q.spin = rnd(-2.5, 2.5)
            q.rot = rnd(0, 6.283)
            q.v = SIMD2(0, -rnd(35, 60))
        case .sakura:
            q.kind = Kind.petal
            q.depth = rnd(0.45, 1)
            q.size = rnd(3.8, 6.2)
            let palette: [SIMD3<Float>] = [SIMD3(1.0, 0.80, 0.86), SIMD3(0.98, 0.70, 0.80), SIMD3(1.0, 0.88, 0.92)]
            let c = palette.randomElement()!
            q.color = SIMD4(c.x, c.y, c.z, 0.95)
            q.spin = rnd(-2, 2)
            q.rot = rnd(0, 6.283)
            q.v = SIMD2(0, -rnd(22, 42))
        case .fireflies:
            q.kind = Kind.firefly
            q.p = SIMD2(rnd(0, w), rnd(0, h))
            q.depth = rnd(0.4, 1)
            q.size = rnd(1.6, 2.8)
            q.color = SIMD4(0.86, 1.0, 0.45, 1)
            q.spin = rnd(0.8, 2.2)        // blink rate
            q.rot = rnd(0, 6.283)         // blink phase
            q.v = SIMD2(cos(q.phase), sin(q.phase)) * rnd(8, 20)
        case .starfall:
            q.kind = Kind.meteor
            q.size = rnd(1.3, 2.2)
            q.color = SIMD4(1.0, 0.95, 0.85, 1)
            let leftward = Bool.random()
            let tilt = rnd(0.35, 0.75)
            let ang = -Float.pi / 2 + (leftward ? -tilt : tilt)
            q.v = SIMD2(cos(ang), sin(ang)) * rnd(550, 900)
            q.p = SIMD2(leftward ? rnd(0.15 * w, 1.15 * w) : rnd(-0.15 * w, 0.85 * w), h + 20)
            q.delay = initial ? rnd(0, 6) : rnd(1.5, 7) / Float(max(0.3, Settings.shared.intensity))
        }
        return q
    }

    private func splash(at p: SIMD2<Float>) -> Particle {
        var q = Particle()
        q.kind = Kind.spark; q.state = .spark; q.transient = true
        q.p = p
        q.v = SIMD2(rnd(-60, 60), rnd(60, 160))
        q.gravity = 900
        q.size = rnd(0.7, 1.3)
        q.life = rnd(0.25, 0.45); q.maxLife = q.life
        q.color = SIMD4(0.8, 0.88, 1.0, 0.7)
        return q
    }

    private func spark(at p: SIMD2<Float>) -> Particle {
        var q = Particle()
        q.kind = Kind.spark; q.state = .spark; q.transient = true
        q.p = p
        let a = rnd(0.15, Float.pi - 0.15)
        q.v = SIMD2(cos(a), sin(a)) * rnd(80, 260)
        q.gravity = 500
        q.size = rnd(0.8, 1.6)
        q.life = rnd(0.5, 1.1); q.maxLife = q.life
        q.color = SIMD4(1.0, rnd(0.75, 0.95), rnd(0.45, 0.7), 1)
        return q
    }

    func snowPuff(at p: SIMD2<Float>, v: SIMD2<Float>) -> Particle {
        var q = Particle()
        q.kind = Kind.snow; q.transient = true
        q.depth = rnd(0.6, 1)
        q.size = rnd(1.1, 2.5)
        q.color = SIMD4(1, 1, 1, 0.92)
        q.phase = rnd(0, 6.283)
        q.p = p
        q.v = v
        return q
    }

    // MARK: Frame update

    func update(dt: Float, cursorGlobal: CGPoint) {
        time += dt
        let base = Float(Settings.shared.wind) * 110
        let gust = sin(time * 0.13) * 0.6 + sin(time * 0.41 + 1.3) * 0.4
        wind = base * (1 + 0.35 * gust) + gust * 18

        syncLedgesIfNeeded()
        updateCursor(dt, cursorGlobal)
        if fullscreenCovered { return }   // nothing visible; save the work
        if mode != .snow { melt(dt) }
        for l in ledgeList { l.relax() }
        stepParticles(dt)
        topUp()
        lightning(dt)
        if Settings.shared.cursorInteraction { scoopPiles(dt) }
        updateSnowplay(dt)
    }

    private func updateCursor(_ dt: Float, _ g: CGPoint) {
        let c = SIMD2<Float>(Float(g.x - origin.x), Float(g.y - origin.y))
        if let prev = cursorPrev {
            let raw = (c - prev) / max(dt, 0.001)
            cursorVel += (raw - cursorVel) * 0.35
        }
        cursorPrev = c
        cursor = c
        if simd_length(cursorVel) < 20 { cursorStill += dt } else { cursorStill = 0 }
    }

    private func melt(_ dt: Float) {
        let rate: Float = mode == .rain ? 1.4 : 0.45
        for l in ledgeList where l.hasSnow {
            for i in l.heights.indices where l.heights[i] > 0 {
                l.heights[i] = max(0, l.heights[i] - rate * dt)
            }
        }
    }

    /// For the demo video: switch weather instantly with a full screen of the new kind.
    func demoSetMode(_ m: Mode) {
        Settings.shared.mode = m
        mode = m
        particles.removeAll { $0.state == .falling && !$0.transient }
        for _ in 0..<targetCount() { particles.append(spawn(initial: true)) }
        if m == .rain { nextLightning = time + 100 }
    }

    func demoLightning() {
        flash = 1
        secondFlashAt = time + 0.18
    }

    private func lightning(_ dt: Float) {
        flash = max(0, flash - dt * 3.5)
        guard mode == .rain else { return }
        if secondFlashAt > 0 && time >= secondFlashAt { flash = 0.8; secondFlashAt = -1 }
        if time >= nextLightning {
            flash = 1
            secondFlashAt = time + rnd(0.12, 0.25)
            nextLightning = time + rnd(14, 40)
        }
    }

    private func topUp() {
        let target = targetCount()
        var live = 0
        for q in particles where !q.transient && q.state != .resting { live += 1 }
        if live < target {
            let add = min(target - live, max(2, target / 60))
            for _ in 0..<add where particles.count < maxParticles { particles.append(spawn(initial: false)) }
        } else if live > target + 5 {
            var excess = live - target
            for i in particles.indices where excess > 0 && !particles[i].transient && particles[i].state == .falling {
                particles[i].transient = true
                if particles[i].kind == Kind.firefly || particles[i].delay > 0 {
                    particles[i].state = .spark
                    particles[i].life = particles[i].delay > 0 ? 0 : 1.2
                    particles[i].maxLife = 1.2
                    particles[i].gravity = 0
                }
                excess -= 1
            }
        }
    }

    // MARK: Particles

    private func stepParticles(_ dt: Float) {
        let w = size.x, h = size.y
        let interact = Settings.shared.cursorInteraction
        let cSpeed = simd_length(cursorVel)
        var spawned: [Particle] = []

        var i = 0
        while i < particles.count {
            var q = particles[i]
            var remove = false

            switch q.state {
            case .spark:
                q.life -= dt
                q.v.y -= q.gravity * dt
                q.v *= (1 - min(1, dt * 0.8))
                q.p += q.v * dt
                if q.life <= 0 { remove = true }

            case .resting:
                q.life += dt
                if let l = ledges[q.ledgeKey], !l.hidden, q.offset < l.width {
                    q.p.x = l.x0 + q.offset
                    q.p.y = l.y + q.size * 0.25
                    if interact && cSpeed > 120 && simd_distance(q.p, cursor) < 30 {
                        q.state = .falling
                        q.v = cursorVel * rnd(0.3, 0.6) + SIMD2(rnd(-30, 30), rnd(60, 170))
                        q.spin = rnd(-6, 6)
                    }
                } else if ledges[q.ledgeKey]?.hidden == true {
                    remove = q.transient
                    if !remove { q = spawn(initial: false) }
                } else {
                    q.state = .falling
                    q.v = SIMD2(rnd(-20, 20), rnd(10, 40))
                }
                if q.state == .resting && q.life > q.maxLife + 2 {
                    if q.transient { remove = true } else { q = spawn(initial: false) }
                }

            case .falling:
                if q.delay > 0 { q.delay -= dt; break }
                applyForces(&q, dt)

                if interact && (q.kind == Kind.snow || q.kind == Kind.leaf || q.kind == Kind.petal) {
                    let d = q.p - cursor
                    let d2 = simd_length_squared(d)
                    if d2 < 70 * 70 && d2 > 0.01 {
                        let dist = d2.squareRoot()
                        let f = 1 - dist / 70
                        let pushK: Float = f * 900 * dt / dist
                        let dragK: Float = f * min(1, dt * 6)
                        let push: SIMD2<Float> = d * pushK
                        let drag: SIMD2<Float> = cursorVel * dragK
                        q.v += push + drag
                    }
                }

                let np = q.p + q.v * dt
                var landed = false
                let collides = q.kind != Kind.firefly && (q.depth >= 0.35 || q.transient || q.kind == Kind.meteor)
                if collides && q.v.y < 0, let hr = hit(from: q.p, to: np) {
                    let (l, b, s) = hr
                    landed = true
                    switch q.kind {
                    case Kind.snow:
                        l.deposit(b, q.size * 0.45)
                        if q.transient { remove = true } else { q = spawn(initial: false) }
                    case Kind.rain:
                        if rnd(0, 1) < 0.7 {
                            spawned.append(splash(at: SIMD2(np.x, s + 0.5)))
                            spawned.append(splash(at: SIMD2(np.x, s + 0.5)))
                        }
                        if q.transient { remove = true } else { q = spawn(initial: false) }
                    case Kind.leaf, Kind.petal:
                        q.state = .resting
                        q.ledgeKey = l.key
                        q.offset = np.x - l.x0
                        q.life = 0
                        q.maxLife = rnd(25, 60)
                        q.rot = rnd(-0.5, 0.5) + (Bool.random() ? 0 : Float.pi)
                        q.p = SIMD2(np.x, l.y + q.size * 0.25)
                    case Kind.meteor:
                        for _ in 0..<10 { spawned.append(spark(at: SIMD2(np.x, s))) }
                        if q.transient { remove = true } else { q = spawn(initial: false) }
                    default:
                        landed = false
                    }
                }

                if !landed {
                    q.p = np
                    if q.kind == Kind.firefly {
                        if q.p.x < 0 { q.v.x = abs(q.v.x); q.phase = 0 }
                        if q.p.x > w { q.v.x = -abs(q.v.x); q.phase = Float.pi }
                        if q.p.y < 0 { q.v.y = abs(q.v.y); q.phase = Float.pi / 2 }
                        if q.p.y > h { q.v.y = -abs(q.v.y); q.phase = -Float.pi / 2 }
                    } else if q.p.y < -40 || (q.p.x < -80 && q.v.x <= 0) || (q.p.x > w + 80 && q.v.x >= 0) || q.p.y > h + 600 {
                        if q.transient { remove = true } else { q = spawn(initial: false) }
                    }
                }
            }

            if remove {
                particles[i] = particles[particles.count - 1]
                particles.removeLast()
            } else {
                particles[i] = q
                i += 1
            }
        }

        let room = maxParticles - particles.count
        if room > 0 { particles.append(contentsOf: spawned.prefix(room)) }
    }

    private func applyForces(_ q: inout Particle, _ dt: Float) {
        switch q.kind {
        case Kind.snow:
            let term = -(25 + 70 * q.depth)
            let tx = wind * (0.4 + 0.6 * q.depth) + sin(time * 0.9 + q.phase) * 14 * (0.5 + q.depth)
            q.v.x += (tx - q.v.x) * min(1, dt * 1.5)
            q.v.y += (term - q.v.y) * min(1, dt * 1.8)
        case Kind.rain:
            let term = -(700 + 500 * q.depth)
            q.v.x += (wind * 1.6 - q.v.x) * min(1, dt * 3)
            q.v.y += (term - q.v.y) * min(1, dt * 3)
        case Kind.leaf, Kind.petal:
            let leaf = q.kind == Kind.leaf
            let variance = 0.8 + 0.4 * (q.phase / 6.283)
            let term: Float = (leaf ? -48 : -32) * variance
            let sway: Float = leaf ? 45 : 32
            let tx = wind * 1.1 + sin(time * (leaf ? 1.6 : 1.2) + q.phase) * sway
            let ty = term + cos(time * (leaf ? 3.2 : 2.4) + q.phase * 2) * (leaf ? 22 : 14)
            q.v.x += (tx - q.v.x) * min(1, dt * 1.6)
            q.v.y += (ty - q.v.y) * min(1, dt * 1.6)
            q.rot += q.spin * dt
            let baseSpin: Float = q.spin > 0 ? 1.5 : -1.5
            q.spin += (baseSpin - q.spin) * min(1, dt * 0.5)
        case Kind.firefly:
            q.phase += rnd(-1.5, 1.5) * dt
            var desired = SIMD2(cos(q.phase), sin(q.phase)) * (14 + 10 * q.depth)
            if Settings.shared.cursorInteraction && cursorStill > 0.6 {
                let d = cursor - q.p
                let dist = simd_length(d)
                if dist < 450 && dist > 1 {
                    let k = q.spin * 5
                    let orbit = SIMD2(cos(time * 0.7 + k), sin(time * 0.9 + k)) * (25 + 30 * q.depth)
                    desired = (cursor + orbit - q.p) * 0.9
                    let len = simd_length(desired)
                    if len > 90 { desired *= 90 / len }
                }
            }
            q.v += (desired - q.v) * min(1, dt * 1.2)
        default:
            break
        }
    }

    private func hit(from a: SIMD2<Float>, to b: SIMD2<Float>) -> (Ledge, Int, Float)? {
        var best: (Ledge, Int, Float)?
        for l in ledgeList {
            guard let i = l.bin(at: b.x), l.caps[i] > 0.5 else { continue }
            let s = l.y + l.heights[i]
            if a.y >= s - 0.01 && b.y < s {
                if best == nil || s > best!.2 { best = (l, i, s) }
            }
        }
        return best
    }

    // MARK: Cursor sweeping through piles

    private func scoopPiles(_ dt: Float) {
        let speed = simd_length(cursorVel)
        let threshold: Float = Settings.shared.snowplay ? 170 : 90
        guard speed > threshold, !isDragging else { return }
        var budget = 60
        let r: Float = 16
        for l in ledgeList {
            guard cursor.y > l.y - 8, cursor.y < l.y + l.maxH + 10 else { continue }
            let lo = max(0, Int((cursor.x - r - l.x0) / Ledge.binW))
            let hi = min(l.heights.count - 1, Int((cursor.x + r - l.x0) / Ledge.binW))
            guard lo <= hi else { continue }
            for b in lo...hi {
                let hgt = l.heights[b]
                guard hgt > 0.3, cursor.y < l.y + hgt + 8 else { continue }
                let take = min(hgt, hgt * min(1, speed * dt * 0.02) + 0.4)
                l.heights[b] -= take
                l.dirty = true
                var n = Int(take / 0.5)
                while n > 0 && budget > 0 && particles.count < maxParticles {
                    n -= 1; budget -= 1
                    let p = SIMD2(l.binX(b), l.y + rnd(0, hgt))
                    let v = cursorVel * rnd(0.25, 0.65) + SIMD2(rnd(-25, 25), rnd(40, 150))
                    particles.append(snowPuff(at: p, v: v))
                }
            }
        }
    }

    /// Knock everything off every ledge.
    func shakeOff() {
        for i in play.trees.indices { play.trees[i].shake = 1 }
        for l in ledgeList {
            breakStacks(on: l.key, vel: SIMD2(rnd(-120, 120), rnd(60, 220)))
            shed(l, vel: SIMD2(rnd(-120, 120), rnd(60, 220)))
        }
    }

    // MARK: Ledges

    private func syncLedgesIfNeeded() {
        let tracker = WindowTracker.shared
        guard tracker.generation != lastGeneration else { return }
        lastGeneration = tracker.generation

        let s = Settings.shared
        let w = size.x
        let visibleTop = Float(visibleFrame.maxY - frame.minY)
        var seen = Set<Int>()
        var clips: [SIMD4<Float>] = []
        dockLocal = nil
        if !s.behindWindows {
            for tw in tracker.windows {
                let r = tw.rect.offsetBy(dx: -origin.x, dy: -origin.y)
                guard r.maxX > 0, r.minX < CGFloat(w), r.maxY > 0, r.minY < CGFloat(size.y) else { continue }
                clips.append(SIMD4(Float(r.minX), Float(r.minY), Float(r.maxX), Float(r.maxY)))
                if clips.count >= 64 { break }
            }
        }
        if Simulation.debugShowAll { clips = [] }   // test flag: ignore app windows
        clipRects = clips
        // Full-screen apps can be made of several stacked windows; check the whole screen,
        // including the menu-bar strip, is covered.
        var covered = !clips.isEmpty
        if covered {
            outer: for gy in 0..<7 {
                for gx in 0..<9 {
                    let p = SIMD2<Float>(w * (Float(gx) + 0.5) / 9, size.y * (Float(gy) + 0.5) / 7)
                    let top = SIMD2<Float>(p.x, size.y - 3)
                    for q in [p, top] where !clips.contains(where: { q.x >= $0.x && q.x <= $0.z && q.y >= $0.y && q.y <= $0.w }) {
                        covered = false
                        break outer
                    }
                }
            }
        }
        fullscreenCovered = covered

        ensure(key: -1, x0: 0, y: 0, width: w, maxH: 12, vel: .zero)
        seen.insert(-1)

        if s.snowOnDock && !s.behindWindows && !fullscreenCovered, let d = tracker.dockRect(frame: frame, visibleFrame: visibleFrame) {
            ensure(key: -2, x0: Float(d.minX), y: Float(d.maxY), width: Float(d.width), maxH: 14, vel: .zero)
            seen.insert(-2)
            dockLocal = d
        }

        if s.pileOnWindows && !s.behindWindows {
            let local = tracker.windows.map { ($0, $0.rect.offsetBy(dx: -origin.x, dy: -origin.y)) }
            for (idx, entry) in local.enumerated() {
                let (tw, r) = entry
                let top = Float(r.maxY)
                guard top > 4, top < visibleTop - 2 else { continue }
                let x0 = max(0, Float(r.minX)), x1 = min(w, Float(r.maxX))
                guard x1 - x0 > 30 else { continue }
                let l = ensure(key: tw.id, x0: x0, y: top, width: x1 - x0, maxH: 22, vel: tw.velocity)
                seen.insert(tw.id)

                // Occlusion: windows in front cover or squash parts of this ledge.
                let fronts = local[0..<idx].map { $0.1 }.filter {
                    CGFloat(x1) > $0.minX && CGFloat(x0) < $0.maxX && Float($0.maxY) >= top - 1
                }
                for b in 0..<l.heights.count {
                    let x = CGFloat(l.binX(b))
                    var cap = min(l.maxH, visibleTop - top)
                    for fr in fronts where x >= fr.minX && x <= fr.maxX {
                        let fMin = Float(fr.minY)
                        if fMin <= top + 1 { cap = 0; break }
                        cap = min(cap, fMin - top)
                    }
                    l.caps[b] = max(0, cap)
                    if l.heights[b] > l.caps[b] { l.heights[b] = l.caps[b] }
                }
            }
        }

        for (key, l) in ledges where !seen.contains(key) {
            if key < 0 {
                breakStacks(on: key, vel: .zero)
                relocateTrees(from: key)
                ledges[key] = nil
            } else if !l.hidden {
                // Window vanished (other Space, minimized, closed). Keep its snow in case it comes back.
                l.hidden = true
                l.hiddenSince = time
            } else if time - l.hiddenSince > 900 {
                relocateTrees(from: key)
                removeStacks(on: key)
                ledges[key] = nil
            }
        }
        ledgeList = ledges.values.filter { !$0.hidden }
    }

    @discardableResult
    private func ensure(key: Int, x0: Float, y: Float, width: Float, maxH: Float, vel: SIMD2<Float>) -> Ledge {
        if let l = ledges[key] {
            let moved = abs(l.y - y) > 0.5 || abs(l.x0 - x0) > 0.5
            if l.hidden {
                l.hidden = false
                if moved { removeStacks(on: key); l.reset(x0: x0, y: y, width: width) }
                else if abs(l.width - width) > 0.5 { l.resize(width: width) }
            } else if moved {
                breakStacks(on: key, vel: vel)
                shed(l, vel: vel)
                l.reset(x0: x0, y: y, width: width)
            } else if abs(l.width - width) > 0.5 {
                l.resize(width: width)
            }
            return l
        }
        let l = Ledge(key: key, x0: x0, y: y, width: width, maxH: maxH)
        ledges[key] = l
        return l
    }

    /// Turn a ledge's pile back into flying snow (window dragged, flung, or shaken).
    private func shed(_ l: Ledge, vel: SIMD2<Float>) {
        var budget = max(0, maxParticles - particles.count)
        for b in 0..<l.heights.count {
            let hgt = l.heights[b]
            guard hgt > 0.4 else { continue }
            var n = min(4, Int(hgt / 1.4) + 1)
            while n > 0 && budget > 0 {
                n -= 1; budget -= 1
                let p = SIMD2(l.x0 + (Float(b) + rnd(0, 1)) * Ledge.binW, l.y + rnd(0, hgt))
                let v = vel * rnd(0.45, 0.9) + SIMD2(rnd(-25, 25), rnd(-10, 40))
                particles.append(snowPuff(at: p, v: v))
            }
        }
        l.clearHeights()
        for i in particles.indices where particles[i].state == .resting && particles[i].ledgeKey == l.key {
            particles[i].state = .falling
            particles[i].v = vel * rnd(0.4, 0.8) + SIMD2(rnd(-20, 20), rnd(20, 80))
            particles[i].spin = rnd(-6, 6)
        }
    }

    // MARK: Output for the renderer

    func writeSprites(_ out: UnsafeMutablePointer<SpriteInstance>, max cap: Int) -> Int {
        if fullscreenCovered { return 0 }
        var n = 0
        if flash > 0.01 {
            out[n] = SpriteInstance(
                a: SIMD4(size.x / 2, size.y / 2, max(size.x, size.y), 0),
                color: SIMD4(0.85, 0.9, 1.0, 0.22 * flash),
                params: SIMD4(Float(Kind.flash), 1, 0, 1))
            n += 1
        }
        for q in particles {
            if n >= cap { break }
            if q.delay > 0 { continue }
            var alpha = q.color.w
            var sz = q.size, rot = q.rot, stretch: Float = 1, yScale: Float = 1
            var center = q.p
            switch q.kind {
            case Kind.snow:
                sz = q.size * 1.6
            case Kind.rain:
                rot = atan2(q.v.y, q.v.x)
                sz = q.size * 1.5
                stretch = (7 + 12 * q.depth) / sz
                center = q.p - SIMD2(cos(rot), sin(rot)) * (sz * stretch * 0.8)
            case Kind.leaf, Kind.petal:
                yScale = q.state == .resting ? 0.6 : 0.3 + 0.7 * abs(cos(time * (1.2 + abs(q.spin) * 0.5) + q.phase))
            case Kind.firefly:
                sz = q.size * 6
                let b = 0.5 + 0.5 * sin(time * q.spin + q.rot)
                alpha *= 0.2 + 0.8 * b * b * b
            case Kind.meteor:
                rot = atan2(q.v.y, q.v.x)
                sz = q.size * 2
                stretch = 16
                center = q.p - SIMD2(cos(rot), sin(rot)) * (sz * stretch * 0.85)
            case Kind.spark:
                sz = q.size * 1.8
            default:
                break
            }
            if q.state == .spark { alpha *= max(0, q.life / q.maxLife) }
            if q.state == .resting && q.life > q.maxLife { alpha *= max(0, 1 - (q.life - q.maxLife) / 2) }
            let noClip: Float = (q.noClip || (q.state == .resting && q.ledgeKey == -2)) ? 1 : 0
            out[n] = SpriteInstance(
                a: SIMD4(center.x, center.y, sz, rot),
                color: SIMD4(q.color.x, q.color.y, q.color.z, alpha),
                params: SIMD4(Float(q.kind), stretch, noClip, yScale))
            n += 1
        }
        return writeSnowplay(out, start: n, max: cap)
    }

    func writePile(_ out: UnsafeMutablePointer<PileVertex>, max cap: Int) -> Int {
        if fullscreenCovered { return 0 }
        var n = 0
        for l in ledgeList {
            let hs = l.heights
            let cnt = hs.count
            guard cnt > 2, l.hasSnow else { continue }
            let clipSign: Float = l.key == -2 ? -1 : 1   // negative shade = never hidden (Dock)
            var prevX: Float = 0, prevH: Float = 0
            for b in 0..<cnt {
                let raw = (hs[max(0, b - 1)] + 2 * hs[b] + hs[min(cnt - 1, b + 1)]) * 0.25
                let edge = Float(min(b, cnt - 1 - b)) * Ledge.binW
                let taper = min(1, (edge + 1.5) / 9).squareRoot()
                var dh = raw * taper
                if dh > 1 { dh += l.lumps[b] * min(1, dh / 6) }
                dh = min(max(0, dh), l.caps[b])
                let x = l.binX(b)
                if b > 0 && (dh > 0.05 || prevH > 0.05) {
                    if n + 6 > cap { return n }
                    let shade0 = clipSign * (0.97 + 0.03 * (l.lumps[max(0, b - 1)] + 0.5))
                    let shade1 = clipSign * (0.97 + 0.03 * (l.lumps[b] + 0.5))
                    let tb0 = 1 - min(1, prevH / 18), tb1 = 1 - min(1, dh / 18)
                    let bl = PileVertex(p: SIMD4(prevX, l.y, tb0, shade0))
                    let br = PileVertex(p: SIMD4(x, l.y, tb1, shade1))
                    let tl = PileVertex(p: SIMD4(prevX, l.y + prevH, 1, shade0))
                    let tr = PileVertex(p: SIMD4(x, l.y + dh, 1, shade1))
                    out[n] = bl; out[n + 1] = br; out[n + 2] = tl
                    out[n + 3] = br; out[n + 4] = tr; out[n + 5] = tl
                    n += 6
                }
                prevX = x
                prevH = dh
            }
        }
        return n
    }
}
