import Cocoa
import simd

// Christmas trees, Santa's sleigh and the gifts he drops.

struct Bauble {
    var tier: Int
    var u: Float        // -1…1 across the tier
    var f: Float        // 0…1 up the tier
    var color: SIMD4<Float>
}

struct XTree {
    var id: Int
    var ledgeKey: Int
    var offset: Float
    var scale: Float
    var baubles: [Bauble]
    var gifts: [(SIMD4<Float>, SIMD4<Float>)]
    var pattern: Int = 0        // 0 colour twinkle · 1 warm white · 2 chase · 3 off
    var shake: Float = 0
    var appear: Float = 0
}

struct Sleigh {
    var x: Float
    var baseY: Float
    var dir: Float
    var t: Float = 0
    var drops: [Float]
    var bonusDrops = 0
}

struct Gift {
    var ledgeKey: Int
    var offset: Float
    var color: SIMD4<Float>
    var ribbon: SIMD4<Float>
    var size: Float
    var age: Float = 0
}

struct FallingGift {
    var p: SIMD2<Float>
    var v: SIMD2<Float>
    var color: SIMD4<Float>
    var ribbon: SIMD4<Float>
    var size: Float
}

private let baubleColors: [SIMD4<Float>] = [
    SIMD4(0.90, 0.15, 0.18, 1), SIMD4(0.98, 0.78, 0.25, 1), SIMD4(0.25, 0.45, 0.95, 1),
    SIMD4(0.85, 0.85, 0.92, 1), SIMD4(0.70, 0.30, 0.85, 1),
]
private let lightColors: [SIMD4<Float>] = [
    SIMD4(1.0, 0.30, 0.30, 1), SIMD4(1.0, 0.85, 0.30, 1), SIMD4(0.35, 0.65, 1.0, 1),
    SIMD4(0.45, 1.0, 0.55, 1), SIMD4(1.0, 0.50, 0.85, 1),
]
private let giftColors: [SIMD4<Float>] = [
    SIMD4(0.85, 0.15, 0.20, 1), SIMD4(0.15, 0.55, 0.35, 1), SIMD4(0.20, 0.40, 0.85, 1),
    SIMD4(0.95, 0.95, 0.95, 1), SIMD4(0.60, 0.25, 0.70, 1),
]
private let ribbonColors: [SIMD4<Float>] = [
    SIMD4(0.98, 0.80, 0.25, 1), SIMD4(0.95, 0.95, 0.95, 1), SIMD4(0.85, 0.15, 0.20, 1),
]
private let tierSpecs: [(w: Float, h: Float)] = [(34, 20), (27, 18), (19, 16)]

extension Simulation {

    // MARK: Update

    func updateFestive(_ dt: Float) {
        for i in play.trees.indices {
            play.trees[i].appear = min(1, play.trees[i].appear + dt * 2)
            play.trees[i].shake = max(0, play.trees[i].shake - dt * 1.5)
        }
        updateSleigh(dt)
        updateGifts(dt)
    }

    // MARK: Trees

    func treeBase(_ t: XTree) -> SIMD2<Float>? {
        guard let l = ledges[t.ledgeKey], !l.hidden else { return nil }
        let x = l.x0 + min(max(t.offset, 0), l.width)
        return SIMD2(x, l.y + l.snowHeight(atX: x) * 0.5)
    }

    func treeIndex(at p: SIMD2<Float>) -> Int? {
        for (i, t) in play.trees.enumerated() {
            guard let b = treeBase(t) else { continue }
            if t.ledgeKey != -2 && isHidden(p) { continue }
            let s = t.scale
            let up = p.y - b.y
            guard up >= 0, up <= 92 * s else { continue }
            let half = 36 * s * (1 - up / (96 * s)) + 6
            if abs(p.x - b.x) < half { return i }
        }
        return nil
    }

    private func makeTree(key: Int, offset: Float) -> XTree {
        var baubles: [Bauble] = []
        for _ in 0..<9 {
            baubles.append(Bauble(tier: Int.random(in: 0..<3), u: rnd(-0.75, 0.75), f: rnd(0.12, 0.62),
                                  color: baubleColors.randomElement()!))
        }
        let gifts = (0..<Int.random(in: 1...3)).map { _ in (giftColors.randomElement()!, ribbonColors.randomElement()!) }
        return XTree(id: play.newID(), ledgeKey: key, offset: offset, scale: rnd(0.95, 1.15),
                     baubles: baubles, gifts: gifts, pattern: 0, shake: 0, appear: 0)
    }

    /// Plant a tree on a visible spot: beside the Dock, then on window tops, then at the Dock's ends.
    func plantTree() -> Bool {
        guard play.trees.count < 6 else { return false }
        let w = size.x
        let visibleTop = Float(screen.visibleFrame.maxY - screen.frame.minY)

        func add(_ l: Ledge, _ x: Float) -> Bool {
            play.trees.append(makeTree(key: l.key, offset: x - l.x0))
            celebrate(at: SIMD2(x, l.y + 90), noClip: l.key == -2)
            return true
        }
        if let g = ledges[-1] {
            for _ in 0..<40 {
                let x = rnd(50, w - 50)
                if let d = dockLocal, x > Float(d.minX) - 45 && x < Float(d.maxX) + 45 { continue }
                if isHidden(SIMD2(x, 20)) || isHidden(SIMD2(x, 95)) { continue }
                if spotIsFree(key: -1, x: x, gap: 50) { return add(g, x) }
            }
        }
        for l in ledgeList.filter({ $0.key >= 0 }).sorted(by: { $0.width > $1.width }) {
            guard l.width > 90, l.y + 105 < visibleTop else { continue }
            for _ in 0..<20 {
                let x = l.x0 + rnd(0.1, 0.9) * l.width
                guard let b = l.bin(at: x), l.caps[b] > 0.5 else { continue }
                if isHidden(SIMD2(x, l.y + 30)) || isHidden(SIMD2(x, l.y + 100)) { continue }
                if spotIsFree(key: l.key, x: x, gap: 50) { return add(l, x) }
            }
        }
        if let d = ledges[-2] {
            for x in [d.x0 + 30, d.x0 + d.width - 30] where spotIsFree(key: -2, x: x, gap: 50) {
                return add(d, x)
            }
        }
        return false
    }

    func removeTrees() { play.trees.removeAll() }

    func treeClicked(_ i: Int) {
        play.trees[i].shake = 1
        play.trees[i].pattern = (play.trees[i].pattern + 1) % 4
        if let b = treeBase(play.trees[i]) {
            let nc = play.trees[i].ledgeKey == -2
            for _ in 0..<3 {
                splat(at: b + SIMD2(rnd(-25, 25), rnd(20, 70) * play.trees[i].scale), r: 4, v: .zero, noClip: nc)
            }
        }
    }

    func dropTree(at p: SIMD2<Float>) {
        guard var t = play.carriedTree else { return }
        play.carriedTree = nil
        let base = p - play.carriedTreeGrab
        var best: Ledge?
        for l in ledgeList {
            guard let b = l.bin(at: base.x), l.caps[b] > 0.5, l.y <= base.y + 8 else { continue }
            if l.key != -2 && isHidden(SIMD2(base.x, l.y + 3)) { continue }
            if best == nil || l.y > best!.y { best = l }
        }
        guard let l = best ?? ledges[-1] else { return }
        t.ledgeKey = l.key
        t.offset = min(max(base.x - l.x0, 0), l.width)
        t.shake = 0.8
        play.trees.append(t)
    }

    /// A ledge is gone for good: move its trees down to the screen bottom.
    func relocateTrees(from key: Int) {
        guard let l = ledges[key], let ground = ledges[-1], key != -1 else { return }
        for i in play.trees.indices where play.trees[i].ledgeKey == key {
            play.trees[i].ledgeKey = -1
            play.trees[i].offset = l.x0 + play.trees[i].offset - ground.x0
            play.trees[i].shake = 1
        }
        play.gifts.removeAll { $0.ledgeKey == key }
    }

    func writeTreesAndGifts(_ w: inout SpriteWriter) {
        for t in play.trees {
            guard let b = treeBase(t) else { continue }
            drawTree(&w, t, base: b, noClip: t.ledgeKey == -2 ? 1 : 0)
        }
        if let t = play.carriedTree {
            drawTree(&w, t, base: cursor - play.carriedTreeGrab, noClip: 1)
        }
        for g in play.gifts {
            guard let l = ledges[g.ledgeKey], !l.hidden else { continue }
            let x = l.x0 + min(g.offset, l.width)
            let c = SIMD2(x, l.y + l.snowHeight(atX: x) * 0.4 + g.size)
            let fade = min(1, max(0, (900 - g.age) / 5))
            drawGift(&w, c, g.size, g.color * SIMD4(1, 1, 1, fade), g.ribbon * SIMD4(1, 1, 1, fade), l.key == -2 ? 1 : 0)
        }
        for g in play.fallingGifts {
            drawGift(&w, g.p, g.size, g.color, g.ribbon, fallingGiftNoClip(g.p) ? 1 : 0)
        }
    }

    private func drawTree(_ w: inout SpriteWriter, _ t: XTree, base b: SIMD2<Float>, noClip nc: Float) {
        let s = t.scale * (0.2 + 0.8 * t.appear)
        let trunk = SIMD4<Float>(0.40, 0.26, 0.15, 1)
        let green = SIMD4<Float>(0.13, 0.45, 0.24, 1)

        // trunk + presents
        w.put(b + SIMD2(0, 7 * s), 4.5 * s, 0, trunk, Kind.box, yScale: 7 / 4.5, nc)
        for (k, g) in t.gifts.enumerated() {
            let side: Float = k % 2 == 0 ? -1 : 1
            let gs = (5.5 - Float(k)) * s
            drawGift(&w, b + SIMD2(side * (14 + Float(k) * 9) * s, gs), gs, g.0, g.1, nc)
        }

        // tiers
        var tiers: [(cx: Float, base: Float, hw: Float, hh: Float)] = []
        var baseY = b.y + 10 * s
        for (i, sp) in tierSpecs.enumerated() {
            let sway = sin(time * 20 + Float(i)) * t.shake * Float(i + 1) * 1.4
            let hw = sp.w * s, hh = sp.h * s
            tiers.append((b.x + sway, baseY, hw, hh))
            w.put(SIMD2(b.x + sway, baseY + hh), hh, 0, green, Kind.tier, stretch: hw / hh, nc)
            baseY += 2 * hh * 0.55
        }

        // baubles
        for bb in t.baubles {
            let tr = tiers[bb.tier]
            let x = tr.cx + bb.u * tr.hw * (1 - bb.f)
            let y = tr.base + 2 * tr.hh * bb.f
            w.put(SIMD2(x, y), 2.6 * s, 0, bb.color, Kind.bauble, nc)
        }

        // string lights
        if t.pattern != 3 {
            var idx = 0
            for tr in tiers {
                for f: Float in [0.22, 0.6] {
                    let n = f < 0.5 ? 6 : 4
                    let half = tr.hw * (1 - f) * 0.85
                    for k in 0..<n {
                        let u = -1 + 2 * Float(k) / Float(n - 1)
                        let x = tr.cx + u * half
                        let y = tr.base + 2 * tr.hh * f - 2.5 * s * (1 - u * u)
                        var col: SIMD4<Float>
                        var a: Float
                        switch t.pattern {
                        case 1:
                            col = SIMD4(1, 0.88, 0.6, 1)
                            a = 0.75 + 0.25 * sin(time * 1.5 + Float(idx) * 0.9)
                        case 2:
                            col = lightColors[idx % lightColors.count]
                            a = (idx + Int(time * 6)) % 4 == 0 ? 1 : 0.25
                        default:
                            col = lightColors[idx % lightColors.count]
                            a = 0.45 + 0.55 * max(0, sin(time * 2.6 + Float(idx) * 1.7))
                        }
                        col.w = a
                        w.put(SIMD2(x, y), 4 * s, 0, col, Kind.light, nc)
                        idx += 1
                    }
                }
            }
        }

        // star
        let top = tiers[2]
        let glow = 0.85 + 0.15 * sin(time * 3)
        w.put(SIMD2(top.cx, top.base + 2 * top.hh + 3 * s), 8 * s, 0, SIMD4(1, 0.85, 0.3, glow), Kind.star, nc)
    }

    private func drawGift(_ w: inout SpriteWriter, _ c: SIMD2<Float>, _ s: Float, _ color: SIMD4<Float>, _ ribbon: SIMD4<Float>, _ nc: Float) {
        w.put(c, s, 0, color, Kind.box, nc)
        w.put(c, s * 0.2, 0, ribbon, Kind.box, yScale: 5, nc)
        w.put(c, s * 0.2, 0, ribbon, Kind.box, stretch: 5, nc)
        w.put(c + SIMD2(-s * 0.35, s * 1.15), s * 0.28, 0.4, ribbon, Kind.dot, stretch: 1.5, nc)
        w.put(c + SIMD2(s * 0.35, s * 1.15), s * 0.28, -0.4, ribbon, Kind.dot, stretch: 1.5, nc)
    }

    // MARK: Santa

    var sleighPos: SIMD2<Float>? {
        guard let s = play.sleigh else { return nil }
        return SIMD2(s.x, s.baseY + sin(s.t * 2.2) * 10)
    }

    /// Santa flies along just above the Dock (or the bottom of the screen).
    func sendSanta() {
        guard play.sleigh == nil else { return }
        let dir: Float = Bool.random() ? 1 : -1
        let w = size.x
        let dockTop = dockLocal.map { Float($0.maxY) } ?? 0
        var drops: [Float] = []
        if let d = dockLocal {
            drops.append(rnd(Float(d.minX) + 20, Float(d.maxX) - 20))
        } else {
            drops.append(rnd(0.25 * w, 0.75 * w))
        }
        play.sleigh = Sleigh(x: dir > 0 ? -240 : w + 240, baseY: dockTop + rnd(75, 115), dir: dir, drops: drops)
    }

    func sleighHit(_ p: SIMD2<Float>) -> Bool {
        guard let s = sleighPos else { return false }
        return abs(p.x - s.x) < 40 && p.y > s.y - 16 && p.y < s.y + 42
    }

    func santaClicked() {
        guard var s = play.sleigh, let pos = sleighPos else { return }
        celebrate(at: pos + SIMD2(0, 30), noClip: true, count: 20)
        if s.bonusDrops < 2 {
            s.bonusDrops += 1
            play.sleigh = s
            dropGift(from: pos, dir: s.dir)
        }
    }

    private func updateSleigh(_ dt: Float) {
        guard var s = play.sleigh else { return }
        let prevX = s.x
        s.t += dt
        s.x += s.dir * 230 * dt
        let pos = SIMD2(s.x, s.baseY + sin(s.t * 2.2) * 10)
        s.drops.removeAll { dx in
            if (prevX - dx) * (s.x - dx) <= 0 { dropGift(from: pos, dir: s.dir); return true }
            return false
        }
        // sparkle trail
        if particles.count < maxParticles && Float.random(in: 0..<1) < 0.85 {
            var q = Particle()
            q.kind = Kind.spark; q.state = .spark; q.transient = true; q.noClip = true
            q.p = pos + SIMD2(-s.dir * 34 + rnd(-4, 4), rnd(-10, 6))
            q.v = SIMD2(-s.dir * rnd(10, 40), rnd(-15, 15))
            q.gravity = 30
            q.size = rnd(0.8, 1.6)
            q.life = rnd(0.8, 1.5); q.maxLife = q.life
            q.color = Bool.random() ? SIMD4(1, 0.9, 0.5, 1) : SIMD4(1, 1, 1, 0.9)
            particles.append(q)
        }
        play.sleigh = (s.dir > 0 && s.x > size.x + 60) || (s.dir < 0 && s.x < -60) ? nil : s
    }

    func writeSleigh(_ w: inout SpriteWriter) {
        guard let sl = play.sleigh, let S = sleighPos else { return }
        let f = sl.dir
        let t = sl.t
        let red = SIMD4<Float>(0.82, 0.10, 0.12, 1)
        let darkRed = SIMD4<Float>(0.62, 0.06, 0.08, 1)
        let gold = SIMD4<Float>(0.98, 0.78, 0.28, 1)
        let white = SIMD4<Float>(0.98, 0.98, 1, 1)
        let skin = SIMD4<Float>(0.98, 0.80, 0.68, 1)
        let black = SIMD4<Float>(0.08, 0.08, 0.10, 1)
        let deer = SIMD4<Float>(0.55, 0.36, 0.20, 1)
        let deerDark = SIMD4<Float>(0.35, 0.22, 0.12, 1)
        let antler = SIMD4<Float>(0.80, 0.66, 0.45, 1)
        let sack = SIMD4<Float>(0.55, 0.38, 0.22, 1)

        // reindeer positions (k = 3 is the lead, with the red nose)
        var deerPos: [SIMD2<Float>] = []
        for k in 0..<4 {
            let fk = Float(k)
            deerPos.append(S + SIMD2(f * (72 + fk * 38), 8 + sin(t * 9 + fk) * 3))
        }

        // reins
        let reinColor = SIMD4<Float>(0.75, 0.55, 0.25, 1)
        w.line(S + SIMD2(f * 24, 10), deerPos[0] + SIMD2(-f * 9, 2), 0.7, reinColor, 1)
        for k in 0..<3 { w.line(deerPos[k] + SIMD2(f * 8, 2), deerPos[k + 1] + SIMD2(-f * 9, 2), 0.7, reinColor, 1) }

        for (k, P) in deerPos.enumerated() {
            let ph = t * 9 + Float(k)
            // legs
            for (lx, off) in [(Float(7), Float(0)), (Float(4), Float(1.6)), (Float(-6), Float(3.1)), (Float(-9), Float(4.7))] {
                let ang = -Float.pi / 2 + f * sin(ph + off) * 0.55
                let start = P + SIMD2(f * lx, -3)
                w.line(start, start + SIMD2(cos(ang), sin(ang)) * 10, 1.1, deerDark, 1)
            }
            w.put(P + SIMD2(-f * 11, 2), 2.2, 0, white, Kind.dot, 1)                             // tail
            w.put(P, 5.5, f * 0.08 * sin(ph), deer, Kind.dot, stretch: 2.1, 1)                   // body
            let head = P + SIMD2(f * 15, 10)
            w.line(P + SIMD2(f * 8, 2), head, 2.6, deer, 1)                                       // neck
            // antlers
            for a in [Float(0.35), Float(0.85)] {
                let ang = Float.pi / 2 - f * a
                let base = head + SIMD2(-f * 1, 2.5)
                let tip = base + SIMD2(cos(ang), sin(ang)) * 7
                w.line(base, tip, 0.8, antler, 1)
                let bAng = ang + f * 0.7
                let mid = base + SIMD2(cos(ang), sin(ang)) * 4
                w.line(mid, mid + SIMD2(cos(bAng), sin(bAng)) * 3.5, 0.7, antler, 1)
            }
            w.put(head, 3.6, f * -0.3, deer, Kind.dot, stretch: 1.4, 1)                          // head
            w.put(head + SIMD2(f * 1.5, 1.5), 0.7, 0, black, Kind.dot, 1)                        // eye
            if k == 3 {
                w.put(head + SIMD2(f * 5, -0.5), 2.0, 0, SIMD4(1, 0.15, 0.1, 1), Kind.light, 1)  // red nose
            } else {
                w.put(head + SIMD2(f * 5, -0.5), 1.2, 0, black, Kind.dot, 1)
            }
        }

        // sack and Santa (behind the sleigh body)
        w.put(S + SIMD2(-f * 15, 19), 10, 0, sack, Kind.dot, stretch: 1.15, 1)
        w.line(S + SIMD2(-f * 18, 28), S + SIMD2(-f * 12, 29), 1.2, deerDark, 1)
        let wave = sin(t * 6) * 0.45
        let shoulder = S + SIMD2(f * 6, 20)
        let armAng = Float.pi / 2 - f * 0.35 + wave * f
        let hand = shoulder + SIMD2(cos(armAng), sin(armAng)) * 11
        w.line(shoulder, hand, 2.3, red, 1)
        w.put(hand, 2.2, 0, black, Kind.dot, 1)
        w.put(S + SIMD2(f * 4, 15), 9, 0, red, Kind.dot, 1)                                       // body
        w.line(S + SIMD2(-f * 4, 11), S + SIMD2(f * 12, 11), 1.4, black, 1)                       // belt
        w.put(S + SIMD2(f * 6, 11), 1.5, 0, gold, Kind.box, 1)
        let headC = S + SIMD2(f * 6, 27)
        w.put(headC, 5, 0, skin, Kind.dot, 1)
        w.put(headC + SIMD2(f * 1.5, -3.5), 5, 0, white, Kind.dot, yScale: 1.05, 1)                // beard
        w.put(headC + SIMD2(f * 3.2, 1.2), 0.8, 0, black, Kind.dot, 1)                            // eye
        let hatRot = Float.pi / 2 + f * 0.65
        let hatBase = headC + SIMD2(-f * 0.5, 4.5)
        let hatDir = SIMD2(cos(hatRot), sin(hatRot))
        w.put(hatBase + hatDir * 7, 4.5, hatRot, red, Kind.cone, stretch: 1.6, 1)
        w.put(hatBase + hatDir * 14, 2.2, 0, white, Kind.dot, 1)                                  // pom-pom
        w.line(hatBase + SIMD2(-5, 0), hatBase + SIMD2(5, 0), 1.7, white, 1)                       // brim

        // sleigh body
        w.put(S + SIMD2(-f * 17, 6), 11, 0, darkRed, Kind.box, yScale: 1.05, 1)                   // high back
        w.put(S + SIMD2(0, 0), 9, 0, red, Kind.box, stretch: 26.0 / 9.0, 1)
        w.put(S + SIMD2(f * 24, 4), 8, 0, red, Kind.dot, 1)                                       // curved front
        w.line(S + SIMD2(-f * 26, 9), S + SIMD2(f * 22, 9), 1.2, gold, 1)                          // trim
        // runners
        w.line(S + SIMD2(-f * 14, -9), S + SIMD2(-f * 14, -13), 1.2, gold, 1)
        w.line(S + SIMD2(f * 14, -9), S + SIMD2(f * 14, -13), 1.2, gold, 1)
        w.line(S + SIMD2(-f * 30, -13), S + SIMD2(f * 30, -13), 1.5, gold, 1)
        w.line(S + SIMD2(f * 30, -13), S + SIMD2(f * 35, -6), 1.5, gold, 1)
        w.line(S + SIMD2(f * 35, -6), S + SIMD2(f * 32, -1), 1.5, gold, 1)
    }

    // MARK: Gifts

    private func dropGift(from p: SIMD2<Float>, dir: Float) {
        play.fallingGifts.append(FallingGift(p: p + SIMD2(-dir * 12, 0), v: SIMD2(dir * 90, 30),
                                             color: giftColors.randomElement()!, ribbon: ribbonColors.randomElement()!,
                                             size: rnd(5.5, 7.5)))
    }

    private func fallingGiftNoClip(_ p: SIMD2<Float>) -> Bool {
        guard let d = dockLocal else { return false }
        return p.x >= Float(d.minX) && p.x <= Float(d.maxX) && p.y <= Float(d.maxY) + 140
    }

    func giftIndex(at p: SIMD2<Float>) -> Int? {
        for (i, g) in play.gifts.enumerated() {
            guard let l = ledges[g.ledgeKey], !l.hidden else { continue }
            if l.key != -2 && isHidden(p) { continue }
            let x = l.x0 + min(g.offset, l.width)
            let c = SIMD2(x, l.y + l.snowHeight(atX: x) * 0.4 + g.size)
            if abs(p.x - c.x) < g.size + 3 && p.y > c.y - g.size - 2 && p.y < c.y + g.size * 1.6 { return i }
        }
        return nil
    }

    func openGift(_ i: Int) {
        let g = play.gifts.remove(at: i)
        guard let l = ledges[g.ledgeKey] else { return }
        let x = l.x0 + min(g.offset, l.width)
        let c = SIMD2(x, l.y + g.size * 1.5)
        celebrate(at: c, noClip: l.key == -2, colors: lightColors + [g.color, g.ribbon], count: 45)
    }

    func dropGifts(on key: Int, vel: SIMD2<Float>) {
        guard let l = ledges[key] else { return }
        for g in play.gifts where g.ledgeKey == key {
            let x = l.x0 + min(g.offset, l.width)
            play.fallingGifts.append(FallingGift(p: SIMD2(x, l.y + g.size), v: vel * 0.6 + SIMD2(0, 60),
                                                 color: g.color, ribbon: g.ribbon, size: g.size))
        }
        play.gifts.removeAll { $0.ledgeKey == key }
    }

    private func updateGifts(_ dt: Float) {
        for i in play.gifts.indices { play.gifts[i].age += dt }
        play.gifts.removeAll { $0.age > 905 }

        var i = 0
        while i < play.fallingGifts.count {
            var g = play.fallingGifts[i]
            g.v.y -= 420 * dt
            g.v.x *= (1 - min(1, dt * 0.6))
            let np = g.p + g.v * dt
            var done = false
            for l in ledgeList {
                guard let b = l.bin(at: np.x), l.caps[b] > 0.5 else { continue }
                let s = l.y + l.snowHeight(atX: np.x) * 0.4
                if g.p.y - g.size >= s - 0.5 && np.y - g.size < s {
                    play.gifts.append(Gift(ledgeKey: l.key, offset: np.x - l.x0, color: g.color, ribbon: g.ribbon, size: g.size))
                    if play.gifts.count > 12 { play.gifts.removeFirst() }
                    splat(at: SIMD2(np.x, s + 1), r: 4, v: .zero, noClip: l.key == -2)
                    done = true
                    break
                }
            }
            if !done {
                g.p = np
                if g.p.y < -20 { done = true }
            }
            if done { play.fallingGifts.remove(at: i) } else { play.fallingGifts[i] = g; i += 1 }
        }
    }
}
