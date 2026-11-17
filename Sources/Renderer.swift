import MetalKit
import simd

/// Must match `Sprite` in the shader (3 × float4).
struct SpriteInstance {
    var a: SIMD4<Float>       // x, y, size, rotation
    var color: SIMD4<Float>
    var params: SIMD4<Float>  // kind, stretch, depth, yScale
}

/// Must match `PV` in the shader.
struct PileVertex {
    var p: SIMD4<Float>       // x, y, gradient t, shade
}

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Sprite { float4 a; float4 color; float4 params; };
struct VOut { float4 pos [[position]]; float2 uv; float2 suv; float2 world; float4 color; float4 params; };

// Is this point covered by an app window? (rects: minX, minY, maxX, maxY; count in u.w)
static bool hiddenByWindow(float2 w, constant float4* rects, constant float4& u) {
    int n = int(u.w + 0.5);
    for (int i = 0; i < n; i++) {
        float4 r = rects[i];
        if (w.x > r.x && w.x < r.z && w.y > r.y && w.y < r.w) return true;
    }
    return false;
}

constant float2 corners[6] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,-1), float2(1,1), float2(-1,1) };

vertex VOut sprite_vs(uint vid [[vertex_id]], uint iid [[instance_id]],
                      const device Sprite* sprites [[buffer(0)]], constant float4& u [[buffer(1)]]) {
    Sprite s = sprites[iid];
    float2 c = corners[vid];
    float2 local = float2(c.x * s.a.z * s.params.y, c.y * s.a.z * s.params.w);
    float cs = cos(s.a.w), sn = sin(s.a.w);
    float2 p = s.a.xy + float2(local.x * cs - local.y * sn, local.x * sn + local.y * cs);
    VOut o;
    o.pos = float4(p / u.xy * 2.0 - 1.0, 0.0, 1.0);
    o.uv = c;
    o.suv = float2(c.x * cs - c.y * sn, c.x * sn + c.y * cs);
    o.world = p;
    o.color = s.color;
    o.params = s.params;
    return o;
}

fragment float4 sprite_fs(VOut in [[stage_in]], constant float4* rects [[buffer(0)]], constant float4& u [[buffer(1)]]) {
    if (in.params.z < 0.5 && hiddenByWindow(in.world, rects, u)) return float4(0.0);
    int kind = int(in.params.x + 0.5);
    float2 uv = in.uv;
    float3 col = in.color.rgb;
    float a = 0.0;
    if (kind == 0) {                       // snowflake
        float d = length(uv);
        a = smoothstep(1.0, 0.2, d);
        a = max(a * a, smoothstep(0.5, 0.3, d));
    } else if (kind == 1) {                // sakura petal, notch at +x
        float body = smoothstep(1.0, 0.82, length(float2(uv.x, uv.y * 1.6)));
        float notch = smoothstep(0.16, 0.3, length(uv - float2(1.0, 0.0)));
        a = body * notch;
        col = mix(col, float3(1.0), 0.35 * saturate(1.0 - length(uv)));
        col *= 0.88 + 0.12 * (uv.x * 0.5 + 0.5);
    } else if (kind == 2) {                // leaf
        float halfW = 0.5 * (1.0 - uv.x * uv.x);
        a = smoothstep(0.06, -0.04, abs(uv.y) - halfW);
        float vein = smoothstep(0.05, 0.0, abs(uv.y)) * step(uv.x, 0.9);
        col *= 0.82 + 0.25 * (0.5 - uv.y);
        col = mix(col, col * 0.55, vein * 0.7);
    } else if (kind == 3) {                // rain streak, head at +x
        float along = uv.x * 0.5 + 0.5;
        a = smoothstep(1.0, 0.2, abs(uv.y)) * along * smoothstep(1.0, 0.85, uv.x);
    } else if (kind == 4) {                // firefly
        float d = length(uv);
        float core = smoothstep(0.2, 0.06, d);
        a = saturate(exp(-d * d * 7.0) * 0.75 + core);
        col = mix(col, float3(1.0, 1.0, 0.85), core);
    } else if (kind == 5) {                // meteor, head at +x
        float along = uv.x * 0.5 + 0.5;
        float width = mix(0.12, 1.0, along);
        float tail = pow(along, 2.2) * smoothstep(width, 0.0, abs(uv.y));
        float dx = (uv.x - 0.9) * in.params.y;
        float head = exp(-(dx * dx + uv.y * uv.y) * 3.0);
        a = saturate(tail * 0.8 + head);
        col = mix(float3(0.6, 0.75, 1.0), col, along);
    } else if (kind == 6) {                // lightning flash
        a = 1.0;
    } else if (kind == 8) {                // snowball (lit in screen space, specks rotate with it)
        float d = length(uv);
        a = smoothstep(1.0, 0.93, d);
        float2 n2 = in.suv;
        float nz = sqrt(saturate(1.0 - dot(n2, n2)));
        float l = saturate(dot(float3(n2, nz), normalize(float3(-0.45, 0.6, 0.65))));
        col = mix(float3(0.70, 0.76, 0.90), float3(1.0), 0.35 + 0.65 * l);
        float sp = smoothstep(0.13, 0.0, length(uv - float2(0.35, 0.2)))
                 + smoothstep(0.10, 0.0, length(uv - float2(-0.4, -0.3)))
                 + smoothstep(0.08, 0.0, length(uv - float2(0.1, -0.55)))
                 + smoothstep(0.09, 0.0, length(uv - float2(-0.2, 0.5)));
        col *= 1.0 - 0.07 * sp;
    } else if (kind == 9) {                // solid dot (coal)
        a = smoothstep(1.0, 0.7, length(uv));
    } else if (kind == 10) {               // cone pointing +x (carrot)
        float halfH = (1.0 - uv.x) * 0.5;
        a = smoothstep(0.08, -0.02, abs(uv.y) - halfH) * smoothstep(-1.0, -0.9, uv.x);
        col *= 0.85 + 0.15 * step(0.0, uv.y);
    } else if (kind == 11) {               // capsule (sticks, scarf, hat brim)
        float st = in.params.y;
        float2 q = float2(max(abs(uv.x * st) - (st - 1.0), 0.0), uv.y);
        a = smoothstep(1.0, 0.75, length(q));
    } else if (kind == 12) {               // box (hat crown, scarf tail, gifts)
        a = smoothstep(1.0, 0.94, max(abs(uv.x), abs(uv.y)));
    } else if (kind == 13) {               // tree tier: triangle, scalloped snowy bottom edge
        float halfW = (1.0 - uv.y) * 0.5;
        float yb = -1.0 + 0.16 * (1.0 - abs(sin(uv.x * 3.14159 * 3.0)));
        a = smoothstep(0.04, -0.03, abs(uv.x) - halfW) * smoothstep(yb - 0.04, yb + 0.04, uv.y);
        col *= 0.78 + 0.32 * (0.5 - uv.x * 0.5) + 0.08 * uv.y;
        float snow = smoothstep(0.22, 0.02, uv.y - yb);
        col = mix(col, float3(0.95, 0.97, 1.0), snow * 0.85);
    } else if (kind == 14) {               // star with glow
        float2 p = float2(uv.x, uv.y) * 1.25;
        const float2 k1 = float2(0.809016994375, -0.587785252292);
        const float2 k2 = float2(-k1.x, k1.y);
        p.x = abs(p.x);
        p -= 2.0 * max(dot(k1, p), 0.0) * k1;
        p -= 2.0 * max(dot(k2, p), 0.0) * k2;
        p.x = abs(p.x);
        p.y -= 0.8;
        float2 ba = 0.42 * float2(-k1.y, k1.x) - float2(0.0, 1.0);
        float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, 0.8);
        float d = length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
        float body = smoothstep(0.04, -0.04, d);
        a = saturate(body + exp(-max(d, 0.0) * 6.0) * 0.45);
        col = mix(col, float3(1.0, 0.97, 0.8), body * 0.35);
    } else if (kind == 15) {               // bauble with highlight
        float d = length(uv);
        a = smoothstep(1.0, 0.82, d);
        float spec = smoothstep(0.38, 0.0, length(uv - float2(-0.35, 0.38)));
        col = col * (0.7 + 0.3 * (uv.y * 0.5 + 0.5)) + spec * 0.65;
    } else if (kind == 16) {               // glowing light bulb
        float d = length(uv);
        float core = smoothstep(0.32, 0.12, d);
        a = saturate(core + exp(-d * d * 5.0) * 0.55);
        col = mix(col, float3(1.0), core * 0.5);
    } else {                               // spark / droplet
        float d = length(uv);
        a = smoothstep(1.0, 0.0, d);
        a *= a;
    }
    a *= in.color.a;
    return float4(col * a, a);
}

struct PV { float4 p; };
struct POut { float4 pos [[position]]; float2 world; float t; float shade; };

vertex POut pile_vs(uint vid [[vertex_id]], const device PV* v [[buffer(0)]], constant float4& u [[buffer(1)]]) {
    PV x = v[vid];
    POut o;
    o.pos = float4(x.p.xy / u.xy * 2.0 - 1.0, 0.0, 1.0);
    o.world = x.p.xy;
    o.t = x.p.z;
    o.shade = x.p.w;
    return o;
}

fragment float4 pile_fs(POut in [[stage_in]], constant float4* rects [[buffer(0)]], constant float4& u [[buffer(1)]]) {
    // Negative shade marks Dock snow, which sits in front of apps and is never hidden.
    if (in.shade > 0.0 && hiddenByWindow(in.world, rects, u)) return float4(0.0);
    float3 deep = float3(0.78, 0.84, 0.95);
    float3 top = float3(0.99, 0.995, 1.0);
    float3 c = mix(deep, top, smoothstep(0.0, 1.0, in.t)) * abs(in.shade);
    float a = 0.97;
    return float4(c * a, a);
}
"""

final class GPU {
    static let shared: GPU? = GPU()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let sprite: MTLRenderPipelineState
    let pile: MTLRenderPipelineState
    static let sampleCount = 4

    private init?() {
        // Prefer the integrated GPU on dual-GPU Intel MacBooks so we don't wake the discrete one.
        let dev = MTLCopyAllDevices().first(where: { $0.isLowPower }) ?? MTLCreateSystemDefaultDevice()
        guard let device = dev, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let lib = try device.makeLibrary(source: shaderSource, options: nil)
            func make(_ v: String, _ f: String) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = lib.makeFunction(name: v)
                d.fragmentFunction = lib.makeFunction(name: f)
                d.rasterSampleCount = GPU.sampleCount
                let ca = d.colorAttachments[0]!
                ca.pixelFormat = .bgra8Unorm
                ca.isBlendingEnabled = true
                ca.rgbBlendOperation = .add
                ca.alphaBlendOperation = .add
                ca.sourceRGBBlendFactor = .one
                ca.sourceAlphaBlendFactor = .one
                ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
                ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                return try device.makeRenderPipelineState(descriptor: d)
            }
            sprite = try make("sprite_vs", "sprite_fs")
            pile = try make("pile_vs", "pile_fs")
        } catch {
            NSLog("Drift: shader setup failed: \(error)")
            return nil
        }
    }
}

final class Renderer: NSObject, MTKViewDelegate {
    static let maxSprites = 8192
    static let maxPile = 120_000

    let gpu: GPU
    let sim: Simulation
    private var spriteBufs: [MTLBuffer] = []
    private var pileBufs: [MTLBuffer] = []
    private var idx = 0
    private let inflight = DispatchSemaphore(value: 3)
    private var last = CACurrentMediaTime()
    var afterUpdate: (() -> Void)?

    init(gpu: GPU, sim: Simulation) {
        self.gpu = gpu
        self.sim = sim
        for _ in 0..<3 {
            spriteBufs.append(gpu.device.makeBuffer(length: MemoryLayout<SpriteInstance>.stride * Renderer.maxSprites, options: .storageModeShared)!)
            pileBufs.append(gpu.device.makeBuffer(length: MemoryLayout<PileVertex>.stride * Renderer.maxPile, options: .storageModeShared)!)
        }
        super.init()
    }

    func resetClock() { last = CACurrentMediaTime() }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(max(now - last, 0.001), 0.05))
        last = now
        sim.size = SIMD2(Float(view.bounds.width), Float(view.bounds.height))
        sim.update(dt: dt, cursorGlobal: NSEvent.mouseLocation)
        afterUpdate?()

        inflight.wait()
        let sb = spriteBufs[idx], pb = pileBufs[idx]
        idx = (idx + 1) % 3
        let nSprites = sim.writeSprites(sb.contents().bindMemory(to: SpriteInstance.self, capacity: Renderer.maxSprites), max: Renderer.maxSprites)
        let nPile = sim.writePile(pb.contents().bindMemory(to: PileVertex.self, capacity: Renderer.maxPile), max: Renderer.maxPile)

        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cb = gpu.queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else {
            inflight.signal()
            return
        }
        let sem = inflight
        cb.addCompletedHandler { _ in sem.signal() }

        var rects = sim.clipRects
        if rects.isEmpty { rects = [SIMD4<Float>(0, 0, 0, 0)] }
        var uni = SIMD4<Float>(Float(view.bounds.width), Float(view.bounds.height), sim.time, Float(sim.clipRects.count))
        let rectBytes = rects.count * MemoryLayout<SIMD4<Float>>.stride
        if nPile > 0 {
            enc.setRenderPipelineState(gpu.pile)
            enc.setVertexBuffer(pb, offset: 0, index: 0)
            enc.setVertexBytes(&uni, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            enc.setFragmentBytes(rects, length: rectBytes, index: 0)
            enc.setFragmentBytes(&uni, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: nPile)
        }
        if nSprites > 0 {
            enc.setRenderPipelineState(gpu.sprite)
            enc.setVertexBuffer(sb, offset: 0, index: 0)
            enc.setVertexBytes(&uni, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            enc.setFragmentBytes(rects, length: rectBytes, index: 0)
            enc.setFragmentBytes(&uni, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nSprites)
        }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}
