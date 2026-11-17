// Renders a demo video of Drift: the real simulation running on a staged desktop,
// with a scripted pointer. Usage: drift-demo <out.mp4>
import Cocoa
import Metal
import AVFoundation
import CoreVideo
import simd

_ = NSApplication.shared

let W = 1920, H = 1080
let FPS = 30
let duration = 56.0
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/drift-demo.mp4"
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let bgraInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

// MARK: - Stage

let screenRect = CGRect(x: 0, y: 0, width: W, height: H)
let menuH: CGFloat = 25
let dockIcons: [(String, NSColor, NSColor)] = [
    ("folder.fill", .init(srgbRed: 0.25, green: 0.60, blue: 1.00, alpha: 1), .init(srgbRed: 0.10, green: 0.40, blue: 0.90, alpha: 1)),
    ("globe", .init(srgbRed: 0.30, green: 0.80, blue: 0.95, alpha: 1), .init(srgbRed: 0.10, green: 0.50, blue: 0.85, alpha: 1)),
    ("envelope.fill", .init(srgbRed: 0.40, green: 0.70, blue: 1.00, alpha: 1), .init(srgbRed: 0.15, green: 0.45, blue: 0.95, alpha: 1)),
    ("message.fill", .init(srgbRed: 0.40, green: 0.90, blue: 0.40, alpha: 1), .init(srgbRed: 0.15, green: 0.70, blue: 0.25, alpha: 1)),
    ("music.note", .init(srgbRed: 1.00, green: 0.40, blue: 0.50, alpha: 1), .init(srgbRed: 0.90, green: 0.15, blue: 0.30, alpha: 1)),
    ("photo.fill", .init(srgbRed: 1.00, green: 0.75, blue: 0.30, alpha: 1), .init(srgbRed: 0.95, green: 0.45, blue: 0.20, alpha: 1)),
    ("calendar", .init(srgbRed: 1.00, green: 0.45, blue: 0.40, alpha: 1), .init(srgbRed: 0.85, green: 0.20, blue: 0.25, alpha: 1)),
    ("note.text", .init(srgbRed: 1.00, green: 0.85, blue: 0.35, alpha: 1), .init(srgbRed: 0.95, green: 0.65, blue: 0.15, alpha: 1)),
    ("terminal.fill", .init(srgbRed: 0.35, green: 0.37, blue: 0.42, alpha: 1), .init(srgbRed: 0.15, green: 0.16, blue: 0.20, alpha: 1)),
    ("gearshape.fill", .init(srgbRed: 0.65, green: 0.67, blue: 0.72, alpha: 1), .init(srgbRed: 0.40, green: 0.42, blue: 0.48, alpha: 1)),
]
let iconSize: CGFloat = 56, iconGap: CGFloat = 10, dockPad: CGFloat = 14
let dockW = CGFloat(dockIcons.count) * iconSize + CGFloat(dockIcons.count - 1) * iconGap + dockPad * 2
let dockRect = CGRect(x: (CGFloat(W) - dockW) / 2, y: 6, width: dockW, height: iconSize + dockPad)
let visibleRect = CGRect(x: 0, y: dockRect.maxY + 8, width: CGFloat(W), height: CGFloat(H) - menuH - dockRect.maxY - 8)

let winA = CGRect(x: 170, y: 250, width: 780, height: 520)      // light notes window
let winB0 = CGRect(x: 1090, y: 300, width: 640, height: 440)    // dark editor (gets dragged)
var winB = winB0
let idA = 101, idB = 102

// MARK: - Drawing helpers

struct LCG {
    var s: UInt64
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(s >> 11) / Double(UInt64(1) << 53))
    }
}

/// Static art is drawn at 2x so it stays sharp when the camera zooms in.
let artScale: CGFloat = 2
func makeImage(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(CGFloat(w) * artScale), height: Int(CGFloat(h) * artScale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: sRGB, bitmapInfo: bgraInfo)!
    ctx.scaleBy(x: artScale, y: artScale)
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}

func withNS(_ ctx: CGContext, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func text(_ s: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
}

func drawSymbol(_ ctx: CGContext, _ name: String, _ pt: CGFloat, center: CGPoint, color: NSColor, weight: NSFont.Weight = .medium) {
    guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: pt, weight: weight)) else { return }
    let tinted = NSImage(size: sym.size, flipped: false) { r in
        sym.draw(in: r)
        color.set()
        r.fill(using: .sourceAtop)
        return true
    }
    withNS(ctx) {
        tinted.draw(in: NSRect(x: center.x - sym.size.width / 2, y: center.y - sym.size.height / 2,
                               width: sym.size.width, height: sym.size.height))
    }
}

// MARK: - Wallpaper: night mountains

func ridge(_ base: CGFloat, _ amps: [CGFloat], _ freqs: [CGFloat], _ phase: CGFloat, _ rng: inout LCG) -> [CGPoint] {
    var pts: [CGPoint] = []
    var x: CGFloat = -10
    while x <= CGFloat(W) + 10 {
        var y = base
        for (i, a) in amps.enumerated() { y += a * sin(x * freqs[i] + phase * CGFloat(i + 1)) }
        y += (rng.next() - 0.5) * 6
        pts.append(CGPoint(x: x, y: y))
        x += 8
    }
    return pts
}

let wallpaper = makeImage(W, H) { ctx in
    var rng = LCG(s: 7)
    let sky = CGGradient(colorsSpace: sRGB, colors: [
        CGColor(srgbRed: 0.04, green: 0.06, blue: 0.18, alpha: 1),
        CGColor(srgbRed: 0.13, green: 0.14, blue: 0.36, alpha: 1),
        CGColor(srgbRed: 0.36, green: 0.27, blue: 0.50, alpha: 1),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: 0, y: 200), options: [.drawsAfterEndLocation])
    for _ in 0..<280 {
        let p = CGPoint(x: rng.next() * CGFloat(W), y: 420 + rng.next() * CGFloat(H - 420))
        let r = 0.5 + rng.next() * 1.3
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.25 + rng.next() * 0.6))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }
    // moon
    let moon = CGPoint(x: 1560, y: 900)
    let glow = CGGradient(colorsSpace: sRGB, colors: [CGColor(srgbRed: 1, green: 0.95, blue: 0.85, alpha: 0.28),
                                                      CGColor(srgbRed: 1, green: 0.95, blue: 0.85, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: moon, startRadius: 0, endCenter: moon, endRadius: 180, options: [])
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0.97, blue: 0.88, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: moon.x - 44, y: moon.y - 44, width: 88, height: 88))

    let layers: [(CGFloat, [CGFloat], [CGFloat], CGFloat, CGColor, CGFloat)] = [
        (560, [95, 40, 14], [0.0042, 0.011, 0.031], 0.7, CGColor(srgbRed: 0.30, green: 0.33, blue: 0.58, alpha: 1), 130),
        (400, [70, 32, 12], [0.0055, 0.014, 0.037], 2.1, CGColor(srgbRed: 0.19, green: 0.20, blue: 0.42, alpha: 1), 90),
        (230, [40, 20, 9], [0.0068, 0.018, 0.045], 4.0, CGColor(srgbRed: 0.10, green: 0.11, blue: 0.25, alpha: 1), 50),
    ]
    for (base, amps, freqs, phase, color, cap) in layers {
        let pts = ridge(base, amps, freqs, phase, &rng)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -10, y: -10))
        for p in pts { path.addLine(to: p) }
        path.addLine(to: CGPoint(x: CGFloat(W) + 10, y: -10))
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(color)
        ctx.fill(screenRect)
        let top = pts.map { $0.y }.max()!
        let snowCap = CGGradient(colorsSpace: sRGB, colors: [CGColor(srgbRed: 0.88, green: 0.91, blue: 1, alpha: 0.95),
                                                            color] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(snowCap, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: top - cap), options: [])
        ctx.restoreGState()
    }
    // pines along the front ridge
    ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.07, blue: 0.17, alpha: 1))
    var x: CGFloat = 10
    while x < CGFloat(W) {
        let h = 26 + rng.next() * 40
        let baseY = 150 + 40 * sin(x * 0.0068 + 4) + rng.next() * 20
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x - h * 0.28, y: baseY))
        p.addLine(to: CGPoint(x: x, y: baseY + h))
        p.addLine(to: CGPoint(x: x + h * 0.28, y: baseY))
        p.closeSubpath()
        ctx.addPath(p)
        ctx.fillPath()
        x += 14 + rng.next() * 30
    }
}

// MARK: - Windows

let margin: CGFloat = 70

func windowImage(_ rect: CGRect, dark: Bool, title: String, content: (CGContext, CGRect) -> Void) -> CGImage {
    makeImage(Int(rect.width + margin * 2), Int(rect.height + margin * 2)) { ctx in
        let r = CGRect(x: margin, y: margin, width: rect.width, height: rect.height)
        let shape = CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(gray: 0, alpha: 0.55))
        ctx.addPath(shape)
        ctx.setFillColor(dark ? CGColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1) : CGColor(gray: 0.985, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let bar = CGRect(x: r.minX, y: r.maxY - 40, width: r.width, height: 40)
        ctx.setFillColor(dark ? CGColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1) : CGColor(gray: 0.93, alpha: 1))
        ctx.fill(bar)
        content(ctx, CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - 40))
        ctx.restoreGState()
        for (i, c) in [CGColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
                       CGColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                       CGColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
            ctx.setFillColor(c)
            ctx.fillEllipse(in: CGRect(x: r.minX + 14 + CGFloat(i) * 20, y: r.maxY - 26.5, width: 13, height: 13))
        }
        let t = text(title, .systemFont(ofSize: 14, weight: .semibold), dark ? NSColor(white: 0.75, alpha: 1) : NSColor(white: 0.35, alpha: 1))
        withNS(ctx) { t.draw(at: CGPoint(x: r.midX - t.size().width / 2, y: r.maxY - 28)) }
        ctx.addPath(shape)
        ctx.setStrokeColor(CGColor(gray: dark ? 1 : 0, alpha: 0.12))
        ctx.setLineWidth(1)
        ctx.strokePath()
    }
}

let imageA = windowImage(winA, dark: false, title: "Weekend Plans") { ctx, area in
    withNS(ctx) {
        text("Weekend Plans", .systemFont(ofSize: 32, weight: .bold), NSColor(white: 0.12, alpha: 1))
            .draw(at: CGPoint(x: area.minX + 44, y: area.maxY - 74))
        text("Saturday · Sunday", .systemFont(ofSize: 17, weight: .regular), NSColor(white: 0.5, alpha: 1))
            .draw(at: CGPoint(x: area.minX + 46, y: area.maxY - 104))
        let items = ["☕️   Hot chocolate by the lake", "⛸   Ice skating on Saturday", "☃️   Build the biggest snowman",
                     "🎄   Decorate the tree", "📸   Photos of the first snow", "🎁   Wrap the presents"]
        for (i, s) in items.enumerated() {
            text(s, .systemFont(ofSize: 21, weight: .regular), NSColor(white: 0.18, alpha: 1))
                .draw(at: CGPoint(x: area.minX + 46, y: area.maxY - 168 - CGFloat(i) * 46))
        }
    }
}

let codeLines = [
    "import Cozy",
    "",
    "struct Snowflake {",
    "    var position: CGPoint",
    "    var drift: Double = .random(in: -1...1)",
    "}",
    "",
    "func letItSnow(on desktop: Desktop) {",
    "    for window in desktop.windows {",
    "        window.top.pile(snow, gently: true)",
    "    }",
    "}",
    "",
    "// roll three snowballs, stack them up ☃️",
]
let keywords: Set<String> = ["import", "struct", "var", "func", "for", "in", "true", "let"]
let types: Set<String> = ["Cozy", "Snowflake", "CGPoint", "Double", "Desktop"]

func colorize(_ line: String) -> NSAttributedString {
    let mono = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
    let plain = NSColor(srgbRed: 0.86, green: 0.87, blue: 0.91, alpha: 1)
    if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
        return text(line, mono, NSColor(srgbRed: 0.47, green: 0.52, blue: 0.58, alpha: 1))
    }
    let out = NSMutableAttributedString(string: line, attributes: [.font: mono, .foregroundColor: plain])
    let re = try! NSRegularExpression(pattern: "[A-Za-z]+|[0-9.]+")
    for m in re.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
        let w = (line as NSString).substring(with: m.range)
        if keywords.contains(w) {
            out.addAttribute(.foregroundColor, value: NSColor(srgbRed: 0.99, green: 0.42, blue: 0.62, alpha: 1), range: m.range)
        } else if types.contains(w) {
            out.addAttribute(.foregroundColor, value: NSColor(srgbRed: 0.42, green: 0.80, blue: 0.96, alpha: 1), range: m.range)
        } else if w.first?.isNumber == true {
            out.addAttribute(.foregroundColor, value: NSColor(srgbRed: 0.85, green: 0.75, blue: 0.45, alpha: 1), range: m.range)
        }
    }
    return out
}

let imageB = windowImage(winB0, dark: true, title: "Snowfall.swift") { ctx, area in
    ctx.setFillColor(CGColor(srgbRed: 0.105, green: 0.115, blue: 0.14, alpha: 1))
    ctx.fill(CGRect(x: area.minX, y: area.minY, width: 54, height: area.height))
    withNS(ctx) {
        for (i, line) in codeLines.enumerated() {
            let y = area.maxY - 40 - CGFloat(i) * 27
            text(String(i + 1), .monospacedSystemFont(ofSize: 15, weight: .regular), NSColor(white: 0.4, alpha: 1))
                .draw(at: CGPoint(x: area.minX + 16, y: y + 2))
            colorize(line).draw(at: CGPoint(x: area.minX + 72, y: y))
        }
    }
}

// MARK: - Dock and menu bar

let dockImage = makeImage(W, Int(dockRect.maxY + 20)) { ctx in
    let shape = CGPath(roundedRect: dockRect, cornerWidth: 20, cornerHeight: 20, transform: nil)
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(srgbRed: 0.85, green: 0.88, blue: 1, alpha: 0.22))
    ctx.fillPath()
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.28))
    ctx.setLineWidth(1)
    ctx.strokePath()
    for (i, icon) in dockIcons.enumerated() {
        let r = CGRect(x: dockRect.minX + dockPad + CGFloat(i) * (iconSize + iconGap), y: dockRect.minY + 9, width: iconSize, height: iconSize)
        let ip = CGPath(roundedRect: r, cornerWidth: 13, cornerHeight: 13, transform: nil)
        ctx.saveGState()
        ctx.addPath(ip)
        ctx.clip()
        let g = CGGradient(colorsSpace: sRGB, colors: [icon.1.cgColor, icon.2.cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.minY), options: [])
        ctx.restoreGState()
        drawSymbol(ctx, icon.0, 26, center: CGPoint(x: r.midX, y: r.midY), color: .white)
        if [0, 1, 3, 8].contains(i) {
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.75))
            ctx.fillEllipse(in: CGRect(x: r.midX - 2, y: dockRect.minY + 2.5, width: 4, height: 4))
        }
    }
}

let menuImage = makeImage(W, Int(menuH)) { ctx in
    ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.07, blue: 0.14, alpha: 0.55))
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(W), height: menuH))
    withNS(ctx) {
        text("Finder", .systemFont(ofSize: 14, weight: .bold), .white).draw(at: CGPoint(x: 22, y: 4))
        var x: CGFloat = 92
        for m in ["File", "Edit", "View", "Go", "Window", "Help"] {
            let t = text(m, .systemFont(ofSize: 14, weight: .regular), .white)
            t.draw(at: CGPoint(x: x, y: 4))
            x += t.size().width + 22
        }
        let clock = text("Mon 17 Dec   9:41", .systemFont(ofSize: 14, weight: .medium), .white)
        clock.draw(at: CGPoint(x: CGFloat(W) - 20 - clock.size().width, y: 4))
    }
    let right = CGFloat(W) - 200
    drawSymbol(ctx, "battery.75", 15, center: CGPoint(x: right - 10, y: menuH / 2), color: .white)
    drawSymbol(ctx, "wifi", 14, center: CGPoint(x: right - 46, y: menuH / 2), color: .white)
    drawSymbol(ctx, "snowflake", 15, center: CGPoint(x: right - 80, y: menuH / 2), color: .white, weight: .semibold)
}

// MARK: - Offscreen Metal renderer

final class OffscreenRenderer {
    let gpu = GPU.shared!
    let msaa: MTLTexture
    let resolve: MTLTexture
    let spriteBuf: MTLBuffer
    let pileBuf: MTLBuffer
    var bytes = [UInt8](repeating: 0, count: W * H * 4)

    init() {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        d.textureType = .type2DMultisample
        d.sampleCount = GPU.sampleCount
        d.usage = .renderTarget
        d.storageMode = .private
        msaa = gpu.device.makeTexture(descriptor: d)!
        let r = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        r.usage = [.renderTarget, .shaderRead]
        r.storageMode = .managed
        resolve = gpu.device.makeTexture(descriptor: r)!
        spriteBuf = gpu.device.makeBuffer(length: MemoryLayout<SpriteInstance>.stride * Renderer.maxSprites, options: .storageModeShared)!
        pileBuf = gpu.device.makeBuffer(length: MemoryLayout<PileVertex>.stride * Renderer.maxPile, options: .storageModeShared)!
    }

    func render(_ sim: Simulation, cam camIn: SIMD4<Float>) -> CGImage {
        var cam = camIn
        let nS = sim.writeSprites(spriteBuf.contents().bindMemory(to: SpriteInstance.self, capacity: Renderer.maxSprites), max: Renderer.maxSprites)
        let nP = sim.writePile(pileBuf.contents().bindMemory(to: PileVertex.self, capacity: Renderer.maxPile), max: Renderer.maxPile)
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = msaa
        rpd.colorAttachments[0].resolveTexture = resolve
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rpd.colorAttachments[0].storeAction = .multisampleResolve
        let cb = gpu.queue.makeCommandBuffer()!
        let enc = cb.makeRenderCommandEncoder(descriptor: rpd)!
        var rects = sim.clipRects
        if rects.isEmpty { rects = [SIMD4<Float>(0, 0, 0, 0)] }
        var uni = SIMD4<Float>(Float(W), Float(H), sim.time, Float(sim.clipRects.count))
        let rectBytes = rects.count * MemoryLayout<SIMD4<Float>>.stride
        let uniBytes = MemoryLayout<SIMD4<Float>>.stride
        if nP > 0 {
            enc.setRenderPipelineState(gpu.pile)
            enc.setVertexBuffer(pileBuf, offset: 0, index: 0)
            enc.setVertexBytes(&uni, length: uniBytes, index: 1)
            enc.setVertexBytes(&cam, length: uniBytes, index: 2)
            enc.setFragmentBytes(rects, length: rectBytes, index: 0)
            enc.setFragmentBytes(&uni, length: uniBytes, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: nP)
        }
        if nS > 0 {
            enc.setRenderPipelineState(gpu.sprite)
            enc.setVertexBuffer(spriteBuf, offset: 0, index: 0)
            enc.setVertexBytes(&uni, length: uniBytes, index: 1)
            enc.setVertexBytes(&cam, length: uniBytes, index: 2)
            enc.setFragmentBytes(rects, length: rectBytes, index: 0)
            enc.setFragmentBytes(&uni, length: uniBytes, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nS)
        }
        enc.endEncoding()
        let blit = cb.makeBlitCommandEncoder()!
        blit.synchronize(resource: resolve)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        bytes.withUnsafeMutableBytes {
            resolve.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4, space: sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: bgraInfo), provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }
}

// MARK: - Simulation setup

let settings = Settings.shared
settings.mode = .snow
settings.intensity = 1.25
settings.wind = 0.15
settings.pileOnWindows = true
settings.snowOnDock = true
settings.behindWindows = false
settings.cursorInteraction = true
settings.snowplay = true

let tracker = WindowTracker.shared
tracker.dockOverride = CGRect(x: dockRect.minX, y: 0, width: dockRect.width, height: dockRect.maxY)
func pushWindows(prevB: CGRect, dt: CGFloat) {
    let v = SIMD2<Float>(Float((winB.minX - prevB.minX) / dt), Float((winB.maxY - prevB.maxY) / dt))
    tracker.inject([TrackedWindow(id: idB, rect: winB, velocity: v), TrackedWindow(id: idA, rect: winA, velocity: .zero)])
}
pushWindows(prevB: winB, dt: 1)

let sim = Simulation(frame: screenRect, visibleFrame: visibleRect)
sim.settingsChanged()
let dt: Float = 1 / Float(FPS)
print("Letting the snow settle…")
for _ in 0..<(240 * FPS) { sim.update(dt: dt, cursorGlobal: CGPoint(x: -500, y: -500)) }

// MARK: - Script

var cur = SIMD2<Float>(1500, 520)
var simDrag = false
var windowDrag: (cursor: SIMD2<Float>, rect: CGRect)?

enum Ease { case inOut, linear }
struct Move {
    let t0: Double, t1: Double
    let ease: Ease
    let target: () -> SIMD2<Float>
    var a: SIMD2<Float>? = nil
    var b: SIMD2<Float>? = nil
    var done = false
}
var moves: [Move] = []
var events: [(t: Double, run: () -> Void)] = []
func move(_ t0: Double, _ t1: Double, _ ease: Ease = .inOut, _ target: @escaping () -> SIMD2<Float>) {
    moves.append(Move(t0: t0, t1: t1, ease: ease, target: target))
}
func at(_ t: Double, _ run: @escaping () -> Void) { events.append((t, run)) }

func ledgeA() -> Ledge { sim.ledges[idA]! }
func onA(_ dx: Float) -> SIMD2<Float> { SIMD2(Float(winA.minX) + dx, ledgeA().y + 2) }
func stackTop(nearX x: Float) -> SIMD2<Float> {
    let l = ledgeA()
    let s = sim.play.stacks.filter { $0.ledgeKey == idA }.min { abs(l.x0 + $0.offset - x) < abs(l.x0 + $1.offset - x) }!
    let top = sim.stackCenters(s, l).last!
    let r = sim.play.carried?.r ?? 8
    return SIMD2(top.x, top.y + s.radii.last! + r + 6)
}
func press() { sim.mouseDown(at: cur); simDrag = true }
func release() { sim.mouseUp(at: cur); simDrag = false }
func click() { sim.mouseDown(at: cur); sim.mouseUp(at: cur) }

var captions: [(t0: Double, t1: Double, text: String)] = [
    (0.3, 4.3, "❄  Drift: live weather for your Mac desktop"),
    (4.6, 9.0, "Snow settles on your windows. Drag one and it slides off."),
    (9.3, 19.8, "Roll snowballs and stack three to build a snowman"),
    (20.1, 32.6, "Decorate a Christmas tree. Santa drops by with gifts."),
    (33.0, 36.3, "Rain  🌧"),
    (36.5, 39.8, "Autumn leaves  🍂"),
    (40.0, 43.3, "Sakura  🌸"),
    (43.5, 46.8, "Fireflies  ✨"),
    (47.0, 50.3, "Starfall  🌠"),
]

// Window drag: grab the editor's title bar and fling it upward.
move(4.8, 5.7) { SIMD2(Float(winB0.midX) + 60, Float(winB0.maxY) - 20) }
at(6.0) { windowDrag = (cur, winB) }
move(6.0, 6.3, .linear) { cur + SIMD2(40, 150) }
at(6.32) { windowDrag = nil }
move(6.6, 7.6) { SIMD2(1450, 210) }

// Snowman: three balls rolled along the notes window's snowy top.
var x1: Float = 0
move(9.2, 9.75) { onA(130) + SIMD2(0, 60) }
move(9.75, 10.05) { onA(130) }
at(10.1) { press() }
move(10.2, 11.8) { onA(340) }
at(11.9) { x1 = cur.x; release() }
move(12.1, 12.45) { onA(440) + SIMD2(0, 60) }
move(12.45, 12.65) { onA(440) }
at(12.7) { press() }
move(12.8, 14.0) { onA(620) }
move(14.1, 14.9) { stackTop(nearX: x1) }
at(15.0) { release() }
move(15.3, 15.6) { onA(670) + SIMD2(0, 60) }
move(15.6, 15.85) { onA(670) }
at(15.9) { press() }
move(16.0, 16.8) { onA(765) }
move(16.9, 17.8) { stackTop(nearX: x1) }
at(17.9) { release() }
move(18.3, 18.9) {
    let l = ledgeA()
    let s = sim.play.stacks.first { $0.ledgeKey == idA && $0.radii.count == 3 }
    return s.map { sim.stackCenters($0, l)[1] } ?? cur
}
at(19.0) { click() }
move(19.3, 19.9) { SIMD2(1280, 560) }

// Christmas trees, then Santa with a gift.
at(20.2) { sim.plantTree(on: -1, x: 1480) }
at(20.6) { sim.plantTree(on: -1, x: 440) }
move(20.6, 21.5) { SIMD2(1480, 45) }
at(21.8) { click() }
at(22.0) { sim.sendSanta(direction: 1) }
at(22.7) { click() }
move(23.2, 24.2) { SIMD2(1160, 330) }
move(28.6, 29.4) {
    guard let g = sim.play.gifts.first, let l = sim.ledges[g.ledgeKey] else { return SIMD2(960, 100) }
    let x = l.x0 + g.offset
    return SIMD2(x, l.y + l.snowHeight(atX: x) * 0.4 + g.size)
}
at(29.7) { click() }
move(30.2, 31.2) { SIMD2(1480, 600) }

// Weather montage.
at(33.0) { sim.demoSetMode(.rain) }
at(34.2) { sim.demoLightning() }
at(36.5) { sim.demoSetMode(.leaves) }
move(38.6, 39.3, .linear) { onA(40) + SIMD2(0, 6) }
move(39.3, 39.7, .linear) { onA(760) + SIMD2(0, 6) }
at(40.0) { sim.demoSetMode(.sakura) }
move(40.2, 41.0) { SIMD2(1450, 640) }
at(43.5) { sim.demoSetMode(.fireflies) }
move(43.5, 44.1) { SIMD2(1010, 600) }
at(47.0) { settings.intensity = 2.6; sim.demoSetMode(.starfall) }
at(50.5) { settings.intensity = 1.25; sim.demoSetMode(.snow) }

// MARK: - Compositing

func drawCaption(_ ctx: CGContext, _ s: String, alpha: CGFloat) {
    let t = text(s, .systemFont(ofSize: 30, weight: .semibold), NSColor(white: 1, alpha: alpha))
    let sz = t.size()
    let pill = CGRect(x: CGFloat(W) / 2 - sz.width / 2 - 30, y: CGFloat(H) - menuH - 40 - sz.height - 22,
                      width: sz.width + 60, height: sz.height + 22)
    let p = CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil)
    ctx.addPath(p)
    ctx.setFillColor(CGColor(srgbRed: 0.03, green: 0.04, blue: 0.10, alpha: 0.55 * alpha))
    ctx.fillPath()
    ctx.addPath(p)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14 * alpha))
    ctx.strokePath()
    withNS(ctx) { t.draw(at: CGPoint(x: pill.minX + 30, y: pill.minY + 11)) }
}

func drawEndCard(_ ctx: CGContext, _ k: CGFloat) {
    ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.03, blue: 0.08, alpha: 0.86 * k))
    ctx.fill(screenRect)
    let a = max(0, min(1, (k - 0.3) / 0.7))
    let lines: [(String, NSFont, CGFloat, CGFloat)] = [
        ("❄  Drift", .systemFont(ofSize: 112, weight: .bold), 1, 600),
        ("Live weather for your Mac desktop", .systemFont(ofSize: 40, weight: .medium), 0.92, 520),
        ("github.com/sparsh1802/drift", .systemFont(ofSize: 28, weight: .regular), 0.75, 440),
    ]
    withNS(ctx) {
        for (s, f, alpha, y) in lines {
            let t = text(s, f, NSColor(white: 1, alpha: alpha * a))
            t.draw(at: CGPoint(x: CGFloat(W) / 2 - t.size().width / 2, y: y))
        }
    }
}

func drawCursor(_ ctx: CGContext, _ view: CGRect) {
    let c: NSCursor
    if simDrag { c = .closedHand } else if windowDrag == nil && sim.wantsMouse() { c = .openHand } else { c = .arrow }
    let img = c.image
    let s: CGFloat = 1.5
    let hot = c.hotSpot
    let z = CGFloat(W) / view.width
    let sx = (CGFloat(cur.x) - view.minX) * z, sy = (CGFloat(cur.y) - view.minY) * z
    let rect = NSRect(x: sx - hot.x * s, y: sy - (img.size.height - hot.y) * s,
                      width: img.size.width * s, height: img.size.height * s)
    withNS(ctx) { img.draw(in: rect) }
}

// Camera: (time, zoom, focus x, focus y). Zooms in on the snowman, then the trees and Santa.
let camKeys: [(Double, CGFloat, CGFloat, CGFloat)] = [
    (0, 1, 960, 540), (9.2, 1, 960, 540), (10.0, 2.5, 585, 830), (19.5, 2.5, 585, 830),
    (20.4, 1.45, 960, 372), (32.0, 1.45, 960, 372), (32.9, 1, 960, 540), (999, 1, 960, 540),
]
/// Visible world rect for time t.
func camera(_ t: Double) -> CGRect {
    var i = 0
    while i < camKeys.count - 2 && t > camKeys[i + 1].0 { i += 1 }
    let a = camKeys[i], b = camKeys[i + 1]
    let u = max(0, min(1, (t - a.0) / (b.0 - a.0)))
    let k = CGFloat(u * u * (3 - 2 * u))
    let z = a.1 + (b.1 - a.1) * k
    let fx = a.2 + (b.2 - a.2) * k, fy = a.3 + (b.3 - a.3) * k
    let w = CGFloat(W) / z, h = CGFloat(H) / z
    let x = max(0, min(CGFloat(W) - w, fx - w / 2)), y = max(0, min(CGFloat(H) - h, fy - h / 2))
    return CGRect(x: x, y: y, width: w, height: h)
}

func ease(_ u: Double, _ e: Ease) -> Float {
    let x = max(0, min(1, u))
    return e == .linear ? Float(x) : Float(x * x * (3 - 2 * x))
}

// MARK: - Render loop

let url = URL(fileURLWithPath: outPath)
try? FileManager.default.removeItem(at: url)
let writer = try! AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: W,
    AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 10_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: 60,
    ],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: W,
    kCVPixelBufferHeightKey as String: H,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let renderer = OffscreenRenderer()
let frames = Int(duration * Double(FPS))
var eventIndex = 0
events.sort { $0.t < $1.t }
let started = Date()

for f in 0..<frames {
    autoreleasepool {
        let t = Double(f) / Double(FPS)
        let prevB = winB

        for i in moves.indices where !moves[i].done && t >= moves[i].t0 {
            if moves[i].a == nil { moves[i].a = cur; moves[i].b = moves[i].target() }
            let u = (t - moves[i].t0) / max(moves[i].t1 - moves[i].t0, 0.001)
            cur = moves[i].a! + (moves[i].b! - moves[i].a!) * ease(u, moves[i].ease)
            if t >= moves[i].t1 { moves[i].done = true }
        }
        while eventIndex < events.count && events[eventIndex].t <= t {
            events[eventIndex].run()
            eventIndex += 1
        }
        if let wd = windowDrag {
            winB = wd.rect.offsetBy(dx: CGFloat(cur.x - wd.cursor.x), dy: CGFloat(cur.y - wd.cursor.y))
        }
        pushWindows(prevB: prevB, dt: CGFloat(dt))
        if simDrag { sim.mouseDragged(at: cur) }
        sim.update(dt: dt, cursorGlobal: CGPoint(x: CGFloat(cur.x), y: CGFloat(cur.y)))
        let view = camera(t)
        let z = CGFloat(W) / view.width
        let overlay = renderer.render(sim, cam: SIMD4(Float(view.minX), Float(view.minY), Float(z), 0))

        while !input.isReadyForMoreMediaData { usleep(2000) }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        guard let buffer = pb else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: W, height: H, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: sRGB, bitmapInfo: bgraInfo)!
        ctx.interpolationQuality = .high
        ctx.saveGState()
        ctx.scaleBy(x: z, y: z)
        ctx.translateBy(x: -view.minX, y: -view.minY)
        ctx.draw(wallpaper, in: screenRect)
        ctx.draw(imageA, in: winA.insetBy(dx: -margin, dy: -margin))
        ctx.draw(imageB, in: winB.insetBy(dx: -margin, dy: -margin))
        ctx.draw(dockImage, in: CGRect(x: 0, y: 0, width: CGFloat(W), height: dockRect.maxY + 20))
        ctx.restoreGState()
        ctx.draw(overlay, in: screenRect)      // already rendered through the camera
        ctx.saveGState()
        ctx.scaleBy(x: z, y: z)
        ctx.translateBy(x: -view.minX, y: -view.minY)
        ctx.draw(menuImage, in: CGRect(x: 0, y: CGFloat(H) - menuH, width: CGFloat(W), height: menuH))
        ctx.restoreGState()

        let endK = CGFloat(max(0, min(1, (t - 50.6) / 1.0)))
        if endK > 0 {
            drawEndCard(ctx, endK)
        } else {
            for c in captions where t >= c.t0 && t <= c.t1 {
                let a = min(1, (t - c.t0) / 0.35, (c.t1 - t) / 0.35)
                drawCaption(ctx, c.text, alpha: CGFloat(max(0, a)))
            }
            drawCursor(ctx, view)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(FPS)))
        if f % 150 == 0 { print("frame \(f)/\(frames)  (\(Int(Date().timeIntervalSince(started)))s)") }
    }
}

input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
if writer.status == .completed {
    print("✓ Wrote \(outPath)")
} else {
    print("✗ Failed: \(String(describing: writer.error))")
    exit(1)
}
