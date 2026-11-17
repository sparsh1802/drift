// Renders the app icon PNGs into an .iconset folder. Usage: make_icon <out.iconset>
import Cocoa

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.32, alpha: 1),
                        NSColor(calibratedRed: 0.27, green: 0.38, blue: 0.68, alpha: 1)])!
        .draw(in: path, angle: 90)

    // a little snow bank along the bottom
    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()
    let bank = NSBezierPath()
    bank.move(to: NSPoint(x: rect.minX, y: rect.minY))
    bank.line(to: NSPoint(x: rect.minX, y: rect.minY + rect.height * 0.16))
    bank.curve(to: NSPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12),
               controlPoint1: NSPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.27),
               controlPoint2: NSPoint(x: rect.minX + rect.width * 0.65, y: rect.minY + rect.height * 0.04))
    bank.line(to: NSPoint(x: rect.maxX, y: rect.minY))
    bank.close()
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    bank.fill()
    // falling dots
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<14 {
        let r = s * CGFloat.random(in: 0.008...0.018, using: &rng)
        let x = CGFloat.random(in: rect.minX...rect.maxX, using: &rng)
        let y = CGFloat.random(in: (rect.minY + rect.height * 0.25)...rect.maxY, using: &rng)
        NSColor(calibratedWhite: 1, alpha: 0.7).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
    }
    NSGraphicsContext.current?.restoreGraphicsState()

    if let sym = NSImage(systemSymbolName: "snowflake", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: s * 0.42, weight: .medium)) {
        let tinted = NSImage(size: sym.size, flipped: false) { r in
            sym.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let sz = tinted.size
        tinted.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2 + s * 0.04, width: sz.width, height: sz.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
