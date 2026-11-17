import Cocoa
import simd

// Snowballs and snowmen, driven by the mouse.
//
//  • Press on a snow pile and drag along it → a snowball rolls up and grows.
//  • Drop it on another ball to stack it. Three stacked balls (any order) become a snowman.
//  • Release while moving fast to throw it; release slowly to leave it where it is.
//  • Drag a ball (or the top of a stack/snowman) to pick it up again. Click a snowman to make it wobble.

extension Kind {
    static let ball: UInt8 = 8
    static let dot: UInt8 = 9
    static let cone: UInt8 = 10
    static let stick: UInt8 = 11
    static let box: UInt8 = 12
    static let tier: UInt8 = 13
    static let star: UInt8 = 14
    static let bauble: UInt8 = 15
    static let light: UInt8 = 16
}

struct SnowStack {
    var id: Int
    var ledgeKey: Int
    var offset: Float
    var radii: [Float]          // bottom → top (largest first), max 3
    var facing: Float
    var scarf: SIMD4<Float>
    var hat: Bool
    var wobble: Float = 0
    var appear: Float = 1
}

struct CarriedBall {
    var p: SIMD2<Float>
    var r: Float
    var rot: Float
    var onLedge: Int?
}

struct FlyingBall {
    var p: SIMD2<Float>
    var v: SIMD2<Float>
    var r: Float
    var rot: Float
    var spin: Float
    var age: Float = 0
    var gentle = false          // dropped, not thrown: settles instead of splatting
}

enum Grab {
    case none
    case ball
    case stack(id: Int, start: SIMD2<Float>)
    case tree(id: Int, start: SIMD2<Float>)
    case carryingTree
}

final class SnowplayState {
    var stacks: [SnowStack] = []
    var carried: CarriedBall?
    var flying: [FlyingBall] = []
    var grab: Grab = .none
    private var nextID = 1
    func newID() -> Int { nextID += 1; return nextID }

    // Festive things (see Festive.swift)
    var trees: [XTree] = []
    var carriedTree: XTree?
    var carriedTreeGrab = SIMD2<Float>(0, 0)
    var sleigh: Sleigh?
    var gifts: [Gift] = []
    var fallingGifts: [FallingGift] = []
}

/// Writes sprite instances into the GPU buffer.
struct SpriteWriter {
    let out: UnsafeMutablePointer<SpriteInstance>
    var n: Int
    let cap: Int

    mutating func put(_ p: SIMD2<Float>, _ size: Float, _ rot: Float, _ color: SIMD4<Float>, _ kind: UInt8,
                      stretch: Float = 1, yScale: Float = 1, _ noClip: Float) {
        guard n < cap else { return }
        out[n] = SpriteInstance(a: SIMD4(p.x, p.y, size, rot), color: color,
                                params: SIMD4(Float(kind), max(1, stretch), noClip, yScale))
        n += 1
    }

    mutating func line(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ th: Float, _ color: SIMD4<Float>, _ noClip: Float) {
        let d = b - a
        let len = simd_length(d)
        guard len > 0.01 else { return }
        put((a + b) * 0.5, th, atan2(d.y, d.x), color, Kind.stick, stretch: (len / 2) / th, noClip)
    }
}

private let scarfColors: [SIMD4<Float>] = [
    SIMD4(0.85, 0.18, 0.18, 1), SIMD4(0.15, 0.55, 0.35, 1), SIMD4(0.22, 0.42, 0.85, 1),
    SIMD4(0.95, 0.65, 0.15, 1), SIMD4(0.60, 0.25, 0.70, 1),
]

extension Ledge {
    func snowHeight(atX x: Float) -> Float {
        guard let b = bin(at: x) else { return 0 }
        let n = heights.count
        return (heights[max(0, b - 1)] + 2 * heights[b] + heights[min(n - 1, b + 1)]) * 0.25
    }
}

extension Simulation {

    /// True if a point is covered by an app window (and so snow there is hidden).
    func isHidden(_ p: SIMD2<Float>) -> Bool {
        if let d = dockLocal, p.x >= Float(d.minX), p.x <= Float(d.maxX), p.y <= Float(d.maxY) + 90 { return false }
        for r in clipRects where p.x > r.x && p.x < r.z && p.y > r.y && p.y < r.w { return true }
        return false
    }

    func newStack(key: Int, offset: Float, radii: [Float], appear: Float) -> SnowStack {
        SnowStack(id: play.newID(), ledgeKey: key, offset: offset, radii: radii.sorted(by: >),
                  facing: Bool.random() ? 1 : -1, scarf: scarfColors.randomElement()!,
                  hat: Float.random(in: 0..<1) < 0.6, wobble: 0, appear: appear)
    }

    private func trimStacks() {
        while play.stacks.count > 16 {
            if let i = play.stacks.firstIndex(where: { $0.radii.count < 3 }) { play.stacks.remove(at: i) }
            else { play.stacks.removeFirst() }
        }
    }

    func stackCenters(_ s: SnowStack, _ l: Ledge) -> [SIMD2<Float>] {
        let x = l.x0 + min(s.offset, l.width)
        let baseY = l.y + l.snowHeight(atX: x) * 0.6
        var out: [SIMD2<Float>] = []
        var cy: Float = 0
        for (k, r0) in s.radii.enumerated() {
            let r = r0 * s.appear
            if k == 0 { cy = baseY + r * 0.85 } else { cy += (s.radii[k - 1] * s.appear + r) * 0.8 }
            let wob = sin(time * 14 + Float(k)) * s.wobble * Float(k) * 2.5
            out.append(SIMD2(x + wob, cy))
        }
        return out
    }

    // MARK: Update

    func updateSnowplay(_ dt: Float) {
        var i = 0
        while i < play.stacks.count {
            var s = play.stacks[i]
            s.appear = min(1, s.appear + dt * 2.5)
            s.wobble = max(0, s.wobble - dt * 1.2)
            if mode != .snow {
                for k in s.radii.indices { s.radii[k] -= 0.08 * dt }
                s.radii.removeAll { $0 < 2.5 }
            }
            if s.radii.isEmpty || ledges[s.ledgeKey] == nil {
                play.stacks.remove(at: i)
                continue
            }
            play.stacks[i] = s
            i += 1
        }
        updateCarried()
        updateFlying(dt)
        updateFestive(dt)
    }

    private func updateCarried() {
        guard var c = play.carried else { return }
        var target = cursor
        var on: Ledge?
        for l in ledgeList {
            guard let b = l.bin(at: target.x), l.caps[b] > 0.5 else { continue }
            let surf = l.y + l.snowHeight(atX: target.x)
            if target.y - c.r * 0.9 < surf && target.y > l.y - 40 {
                if on == nil || l.y > on!.y { on = l }
            }
        }
        if let l = on { target.y = l.y + l.snowHeight(atX: target.x) + c.r * 0.9 }
        let dx = target.x - c.p.x
        c.rot -= dx / max(c.r, 1)
        if let l = on, abs(dx) > 0.01 {
            // Rolling along a pile picks up snow.
            var gathered: Float = 0
            let lo = max(0, Int((target.x - c.r * 0.75 - l.x0) / Ledge.binW))
            let hi = min(l.heights.count - 1, Int((target.x + c.r * 0.75 - l.x0) / Ledge.binW))
            if lo <= hi {
                for b in lo...hi {
                    let take = min(l.heights[b], abs(dx) * 0.25)
                    l.heights[b] -= take
                    gathered += take
                }
                l.dirty = true
            }
            c.r = min(30, c.r + gathered * 0.25 / max(c.r, 1))
        }
        c.p = target
        c.onLedge = on?.key
        play.carried = c
    }

    // MARK: Mouse

    var isDragging: Bool {
        if case .none = play.grab { return false }
        return true
    }

    /// Should the overlay take the mouse right now? Only over interactive things, so
    /// clicks everywhere else still go to the apps and desktop underneath.
    func wantsMouse() -> Bool {
        if isDragging { return true }
        guard !fullscreenCovered, Settings.shared.cursorInteraction else { return false }
        let p = cursor
        if sleighHit(p) || giftIndex(at: p) != nil || treeIndex(at: p) != nil { return true }
        if Settings.shared.snowplay {
            if stackIndex(at: p) != nil || pileLedge(at: p) != nil { return true }
            if play.flying.contains(where: { simd_distance($0.p, p) < $0.r + 6 }) { return true }
        }
        return false
    }

    func stackIndex(at p: SIMD2<Float>) -> Int? {
        for (i, s) in play.stacks.enumerated() {
            guard let l = ledges[s.ledgeKey], !l.hidden else { continue }
            if l.key != -2 && isHidden(p) { continue }
            for (k, c) in stackCenters(s, l).enumerated() where simd_distance(c, p) < s.radii[k] + 2 { return i }
        }
        return nil
    }

    func pileLedge(at p: SIMD2<Float>) -> Ledge? {
        var best: Ledge?
        for l in ledgeList {
            guard let b = l.bin(at: p.x), l.caps[b] > 0.5 else { continue }
            let h = l.snowHeight(atX: p.x)
            guard h >= 1.5, p.y > l.y - 2, p.y < l.y + h + 6 else { continue }
            if l.key != -2 && isHidden(SIMD2(p.x, l.y + 1)) { continue }
            if best == nil || l.y > best!.y { best = l }
        }
        return best
    }

    func mouseDown(at p: SIMD2<Float>) {
        cursor = p
        if sleighHit(p) { santaClicked(); return }
        if let gi = giftIndex(at: p) { openGift(gi); return }
        if let ti = treeIndex(at: p) { play.grab = .tree(id: play.trees[ti].id, start: p); return }
        guard Settings.shared.snowplay else { return }
        if let si = stackIndex(at: p) { play.grab = .stack(id: play.stacks[si].id, start: p); return }
        if let fi = play.flying.firstIndex(where: { simd_distance($0.p, p) < $0.r + 6 }) {
            let b = play.flying.remove(at: fi)
            play.carried = CarriedBall(p: b.p, r: b.r, rot: b.rot, onLedge: nil)
            play.grab = .ball
            return
        }
        if let l = pileLedge(at: p) {
            // Scoop a handful of snow to start a ball.
            let lo = max(0, Int((p.x - 6 - l.x0) / Ledge.binW))
            let hi = min(l.heights.count - 1, Int((p.x + 6 - l.x0) / Ledge.binW))
            if lo <= hi { for b in lo...hi { l.heights[b] = max(0, l.heights[b] - 1.2) } }
            l.dirty = true
            play.carried = CarriedBall(p: SIMD2(p.x, l.y + l.snowHeight(atX: p.x) + 4), r: 4.5, rot: 0, onLedge: l.key)
            play.grab = .ball
        }
    }

    func mouseDragged(at p: SIMD2<Float>) {
        cursor = p
        switch play.grab {
        case .stack(let id, let start):
            guard simd_distance(p, start) > 4, let si = play.stacks.firstIndex(where: { $0.id == id }),
                  let l = ledges[play.stacks[si].ledgeKey] else { return }
            // Lift the top ball off the stack.
            let top = stackCenters(play.stacks[si], l).last!
            let r = play.stacks[si].radii.removeLast()
            if play.stacks[si].radii.isEmpty { play.stacks.remove(at: si) } else { play.stacks[si].wobble = 0.5 }
            play.carried = CarriedBall(p: top, r: r, rot: 0, onLedge: nil)
            play.grab = .ball
        case .tree(let id, let start):
            guard simd_distance(p, start) > 4, let ti = play.trees.firstIndex(where: { $0.id == id }),
                  let base = treeBase(play.trees[ti]) else { return }
            play.carriedTreeGrab = start - base
            play.carriedTree = play.trees.remove(at: ti)
            play.grab = .carryingTree
        default:
            break
        }
    }

    func mouseUp(at p: SIMD2<Float>) {
        cursor = p
        switch play.grab {
        case .ball:
            releaseBall()
        case .stack(let id, _):
            if let si = play.stacks.firstIndex(where: { $0.id == id }) { play.stacks[si].wobble = 1 }
        case .tree(let id, _):
            if let ti = play.trees.firstIndex(where: { $0.id == id }) { treeClicked(ti) }
        case .carryingTree:
            dropTree(at: p)
        case .none:
            break
        }
        play.grab = .none
    }

    private func releaseBall() {
        guard let c = play.carried else { return }
        play.carried = nil

        // Dropped onto another ball / stack → stack it.
        for si in play.stacks.indices where play.stacks[si].radii.count < 3 {
            let s = play.stacks[si]
            guard let l = ledges[s.ledgeKey], !l.hidden else { continue }
            let top = stackCenters(s, l).last!
            let tr = s.radii.last!
            if abs(c.p.x - top.x) < tr + c.r * 0.6 && c.p.y > top.y - tr * 0.3 && c.p.y < top.y + tr + c.r * 2 + 40 {
                addBall(c.r, toStack: si)
                return
            }
        }

        let v = cursorVel
        let speed = simd_length(v)
        if speed > 500 {
            var tv = v * 1.1
            if speed > 2400 { tv *= 2400 / speed }
            launch(FlyingBall(p: c.p, v: tv, r: c.r, rot: c.rot, spin: -tv.x / max(c.r, 1) * 0.5))
        } else if let key = c.onLedge, let l = ledges[key] {
            parkBall(c.r, x: c.p.x, on: l)
        } else {
            launch(FlyingBall(p: c.p, v: v * 0.4, r: c.r, rot: c.rot, spin: -v.x * 0.01, gentle: true))
        }
    }

    private func parkBall(_ r: Float, x: Float, on l: Ledge) {
        let off = x - l.x0
        if let idx = play.stacks.firstIndex(where: {
            $0.ledgeKey == l.key && $0.radii.count < 3 && abs($0.offset - off) < max($0.radii[0], r) * 0.9
        }) {
            addBall(r, toStack: idx)
        } else {
            play.stacks.append(newStack(key: l.key, offset: off, radii: [r], appear: 1))
            trimStacks()
        }
    }

    private func addBall(_ radius: Float, toStack idx: Int) {
        play.stacks[idx].radii.append(radius)
        play.stacks[idx].radii.sort(by: >)
        play.stacks[idx].wobble = 0.6
        if play.stacks[idx].radii.count == 3, let l = ledges[play.stacks[idx].ledgeKey] {
            let top = stackCenters(play.stacks[idx], l).last!
            celebrate(at: top + SIMD2(0, play.stacks[idx].radii[2]), noClip: l.key == -2)
        }
    }

    private func launch(_ b: FlyingBall) {
        play.flying.append(b)
        if play.flying.count > 12 { play.flying.removeFirst() }
    }

    private func updateFlying(_ dt: Float) {
        var i = 0
        while i < play.flying.count {
            var b = play.flying[i]
            b.age += dt
            b.v.y -= 900 * dt
            b.v *= (1 - min(1, dt * 0.15))
            b.rot += b.spin * dt
            let np = b.p + b.v * dt
            let speed = simd_length(b.v)
            var done = false

            // Hit a snowman or a parked ball.
            outer: for si in play.stacks.indices {
                let s = play.stacks[si]
                guard let l = ledges[s.ledgeKey], !l.hidden, s.appear > 0.9 else { continue }
                let cs = stackCenters(s, l)
                for (k, c) in cs.enumerated() {
                    let rr = s.radii[k]
                    guard simd_distance(np, c) < b.r + rr * 0.9 else { continue }
                    let isTop = k == cs.count - 1
                    if isTop && s.radii.count < 3 && b.v.y < 0 && np.y > c.y + rr * 0.3 && (speed < 900 || b.gentle) {
                        addBall(b.r, toStack: si)
                    } else if isTop && s.radii.count == 3 && speed > 500 && !b.gentle {
                        let head = play.stacks[si].radii.removeLast()   // knocked the head off!
                        play.stacks[si].wobble = 1
                        play.flying.append(FlyingBall(p: c, v: b.v * 0.6 + SIMD2(0, 220), r: head, rot: 0, spin: b.v.x * 0.02))
                        splat(at: np, r: b.r * 0.7, v: b.v)
                    } else {
                        play.stacks[si].wobble = 1
                        splat(at: np, r: b.r, v: b.v)
                    }
                    done = true
                    break outer
                }
            }

            // Hit a tree.
            if !done, let ti = treeIndex(at: np) {
                play.trees[ti].shake = 1
                splat(at: np, r: b.r, v: b.v)
                done = true
            }

            // Land on a ledge: gentle drops and soft landings stay as a ball; hard ones splat.
            if !done && b.v.y < 0 {
                for l in ledgeList {
                    guard let bin = l.bin(at: np.x), l.caps[bin] > 0.5 else { continue }
                    let s = l.y + l.snowHeight(atX: np.x)
                    if b.p.y - b.r * 0.85 >= s - 0.5 && np.y - b.r * 0.85 < s {
                        if b.gentle || speed < 420 {
                            parkBall(b.r, x: np.x, on: l)
                        } else {
                            splat(at: SIMD2(np.x, s + 2), r: b.r, v: b.v, noClip: l.key == -2)
                            let spread = Int(b.r / Ledge.binW)
                            for k in -spread...spread {
                                let j = bin + k
                                if j >= 0 && j < l.heights.count { l.deposit(j, b.r * 0.12) }
                            }
                        }
                        done = true
                        break
                    }
                }
            }

            // Hit an app window.
            if !done && isHidden(np) && !isHidden(b.p) {
                splat(at: b.p, r: b.r, v: SIMD2(-b.v.x * 0.3, abs(b.v.y) * 0.2))
                done = true
            }

            if !done {
                b.p = np
                if b.p.x < b.r && b.v.x < 0 { b.v.x = -b.v.x * 0.45; b.spin = -b.spin }
                if b.p.x > size.x - b.r && b.v.x > 0 { b.v.x = -b.v.x * 0.45; b.spin = -b.spin }
                if b.p.y < -b.r * 2 || b.age > 12 { done = true }
            }

            if done { play.flying.remove(at: i) } else { play.flying[i] = b; i += 1 }
        }
    }

    func splat(at p: SIMD2<Float>, r: Float, v: SIMD2<Float>, noClip: Bool = false) {
        let n = min(60, max(6, Int(r * r * 0.12)))
        for _ in 0..<n where particles.count < maxParticles {
            let a = rnd(0, 6.283)
            let sp = rnd(40, 160) * (0.5 + r / 20)
            let pv = v * 0.15 + SIMD2(cos(a), abs(sin(a)) * 1.2) * sp
            var q = snowPuff(at: p + SIMD2(cos(a), sin(a)) * rnd(0, r * 0.6), v: pv)
            q.noClip = noClip
            particles.append(q)
        }
    }

    func celebrate(at p: SIMD2<Float>, noClip: Bool = false, colors: [SIMD4<Float>]? = nil, count: Int = 14) {
        for _ in 0..<count where particles.count < maxParticles {
            var q = Particle()
            q.kind = Kind.spark; q.state = .spark; q.transient = true
            q.noClip = noClip
            q.p = p
            let a = rnd(0.2, Float.pi - 0.2)
            q.v = SIMD2(cos(a), sin(a)) * rnd(60, 200)
            q.gravity = 250
            q.size = rnd(0.9, 1.7)
            q.life = rnd(0.6, 1.3); q.maxLife = q.life
            q.color = colors?.randomElement() ?? SIMD4(1, 0.95, 0.7, 1)
            particles.append(q)
        }
    }

    /// Window moved/closed: its snowmen tumble off and burst.
    func breakStacks(on key: Int, vel: SIMD2<Float>) {
        guard let l = ledges[key] else { return }
        for s in play.stacks where s.ledgeKey == key {
            for (k, c) in stackCenters(s, l).enumerated() { splat(at: c, r: s.radii[k], v: vel, noClip: key == -2) }
        }
        play.stacks.removeAll { $0.ledgeKey == key }
        dropGifts(on: key, vel: vel)
    }

    func removeStacks(on key: Int) {
        play.stacks.removeAll { $0.ledgeKey == key }
        play.gifts.removeAll { $0.ledgeKey == key }
    }

    /// Build a snowman on a visible spot (Dock first, then window tops, then the screen bottom).
    func buildSnowman() -> Bool {
        let visibleTop = Float(screen.visibleFrame.maxY - screen.frame.minY)
        var cands: [Ledge] = []
        if let d = ledges[-2], !d.hidden { cands.append(d) }
        cands += ledgeList.filter { $0.key >= 0 }.sorted { $0.width > $1.width }
        if let g = ledges[-1] { cands.append(g) }
        for l in cands {
            guard l.width > 70, l.y + 80 < visibleTop else { continue }
            for _ in 0..<24 {
                let x = l.x0 + rnd(0.15, 0.85) * l.width
                guard let b = l.bin(at: x), l.caps[b] > 0.5 else { continue }
                if l.key != -2 && (isHidden(SIMD2(x, l.y + 30)) || isHidden(SIMD2(x, l.y + 70))) { continue }
                if !spotIsFree(key: l.key, x: x, gap: 45) { continue }
                play.stacks.append(newStack(key: l.key, offset: x - l.x0,
                                            radii: [rnd(17, 21), rnd(12, 14.5), rnd(8.5, 10)], appear: 0))
                trimStacks()
                splat(at: SIMD2(x, l.y + 4), r: 8, v: .zero, noClip: l.key == -2)
                celebrate(at: SIMD2(x, l.y + 70), noClip: l.key == -2)
                return true
            }
        }
        return false
    }

    func spotIsFree(key: Int, x: Float, gap: Float) -> Bool {
        guard let l = ledges[key] else { return false }
        if play.stacks.contains(where: { $0.ledgeKey == key && abs(l.x0 + $0.offset - x) < gap }) { return false }
        if play.trees.contains(where: { $0.ledgeKey == key && abs(l.x0 + $0.offset - x) < gap + 30 }) { return false }
        return true
    }

    // MARK: Drawing

    func writeSnowplay(_ out: UnsafeMutablePointer<SpriteInstance>, start: Int, max cap: Int) -> Int {
        var w = SpriteWriter(out: out, n: start, cap: cap)
        let white = SIMD4<Float>(1, 1, 1, 1)
        let coal = SIMD4<Float>(0.08, 0.08, 0.10, 1)
        let wood = SIMD4<Float>(0.36, 0.24, 0.14, 1)
        let carrot = SIMD4<Float>(0.96, 0.50, 0.12, 1)

        writeTreesAndGifts(&w)

        for s in play.stacks {
            guard let l = ledges[s.ledgeKey], !l.hidden else { continue }
            let nc: Float = l.key == -2 ? 1 : 0
            let cs = stackCenters(s, l)
            let rs = s.radii.map { $0 * s.appear }
            let full = rs.count == 3
            let f = s.facing

            if full {   // stick arms, behind the body
                let m = cs[1], rm = rs[1]
                for side: Float in [-1, 1] {
                    let wave = sin(time * 1.6 + s.offset) * 0.08
                    let ang: Float = side > 0 ? 0.5 + wave : Float.pi - 0.5 - wave
                    let dir = SIMD2(cos(ang), sin(ang))
                    let start = m + SIMD2(side * rm * 0.7, rm * 0.15)
                    let len = rm * 1.4
                    let th = max(1.0, rm * 0.07)
                    w.line(start, start + dir * len, th, wood, nc)
                    let tAng = ang + (side > 0 ? 0.7 : -0.7)
                    let tStart = start + dir * (len * 0.68)
                    w.line(tStart, tStart + SIMD2(cos(tAng), sin(tAng)) * (len * 0.3), th * 0.85, wood, nc)
                }
            }

            for k in cs.indices {
                w.put(cs[k], rs[k], 0, white, Kind.ball, nc)
                if full && k == 1 {   // coal buttons
                    for j in 0..<3 {
                        let y = cs[1].y + rs[1] * (0.4 - 0.4 * Float(j))
                        w.put(SIMD2(cs[1].x + f * rs[1] * 0.12, y), max(1.1, rs[1] * 0.09), 0, coal, Kind.dot, nc)
                    }
                }
            }

            if full {
                let h = cs[2], rh = rs[2]
                let neckY = h.y - rh * 0.85
                let sth = max(1.4, rh * 0.2)
                w.put(SIMD2(h.x, neckY), sth, -0.06 * f, s.scarf, Kind.stick, stretch: rh * 0.95 / sth, nc)
                let tailW = max(1.2, rh * 0.14)
                w.put(SIMD2(h.x - f * rh * 0.45, neckY - rh * 0.45), tailW, 0.18 * f,
                      s.scarf * SIMD4(0.85, 0.85, 0.85, 1), Kind.box, yScale: rh * 0.42 / tailW, nc)
                for side: Float in [-1, 1] {
                    w.put(SIMD2(h.x + side * rh * 0.28 + f * rh * 0.12, h.y + rh * 0.22), max(1.1, rh * 0.1), 0, coal, Kind.dot, nc)
                }
                for j in 0..<5 {
                    let t = Float(j - 2)
                    w.put(SIMD2(h.x + f * rh * 0.12 + t * rh * 0.15, h.y - rh * 0.38 + t * t * rh * 0.035),
                          max(0.8, rh * 0.055), 0, coal, Kind.dot, nc)
                }
                let nl = rh * 0.75, nth = max(1.1, rh * 0.13)
                w.put(SIMD2(h.x + f * (rh * 0.25 + nl / 2), h.y - rh * 0.02), nth, f > 0 ? 0 : Float.pi, carrot, Kind.cone,
                      stretch: (nl / 2) / nth, nc)
                if s.hat {
                    let brimY = h.y + rh * 0.8
                    let bth = max(1.1, rh * 0.09)
                    w.put(SIMD2(h.x, brimY), bth, 0, coal, Kind.stick, stretch: rh * 0.85 / bth, nc)
                    let cw = rh * 0.55, ch = rh * 0.5
                    w.put(SIMD2(h.x, brimY + ch), cw, 0, coal, Kind.box, yScale: ch / cw, nc)
                    w.put(SIMD2(h.x, brimY + rh * 0.14), cw, 0, s.scarf, Kind.box, yScale: rh * 0.08 / cw, nc)
                }
            }
        }

        if let c = play.carried {
            w.put(c.p, c.r, c.rot, white, Kind.ball, 1)   // you're holding it: always visible
        }
        for b in play.flying {
            w.put(b.p, b.r, b.rot, white, Kind.ball, 0)
        }
        writeSleigh(&w)
        return w.n
    }
}
