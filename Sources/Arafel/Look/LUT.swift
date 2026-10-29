import Foundation

/// Lookup tables for `CIColorCube`. Custom Core Image kernels need the Metal compiler, which ships only with
/// Xcode, so every curve and the palette are baked into tables.
enum LUT {
    static let size = 64

    /// Output depends only on the red input; depth is gray, so r = g = b.
    static func ofRed(_ f: (Double) -> SIMD3<Double>) -> Data {
        let n = size
        var row = [Float](repeating: 0, count: n * 4)
        for i in 0..<n {
            let c = f(Double(i) / Double(n - 1))
            row[i * 4] = Float(c.x); row[i * 4 + 1] = Float(c.y); row[i * 4 + 2] = Float(c.z); row[i * 4 + 3] = 1
        }
        var all = [Float]()
        all.reserveCapacity(n * n * n * 4)
        for _ in 0..<(n * n) { all.append(contentsOf: row) }
        return all.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Depth stretched between the photo's percentiles to 0 far, 1 near, then shaped by tone.
    static func nearness(_ d: Double, lo: Double, hi: Double, tone: Double) -> Double {
        let t = min(1, max(0, (d - lo) / max(hi - lo, 0.001)))
        return pow(t, tone)
    }

    /// Depth in, linear RGB out.
    static func palette(_ look: Look, lo: Double, hi: Double) -> Data {
        ofRed { d in
            let t = nearness(d, lo: lo, hi: hi, tone: look.tone)
            return gradient(look.stops, at: look.invert ? t : 1 - t)
        }
    }

    /// How much of the photo shows through: nearest first, the far end never.
    static func showMask(_ amount: Double, lo: Double, hi: Double) -> Data {
        ofRed { d in
            let t = nearness(d, lo: lo, hi: hi, tone: 1)
            // The reveal moves farther as amount rises, over a soft band.
            let edge = 1 - amount
            let x = min(1, max(0, (t - edge * 0.9) / 0.35))
            let m = x * x * (3 - 2 * x) * min(1, amount * 1.4)
            return SIMD3(repeating: m)
        }
    }

    static let weightSize = 32
    /// Grain strength by sRGB luminance: 1 in the mid-tones, 0.5 at black and white.
    static let grainWeight: Data = {
        let n = weightSize
        var all = [Float]()
        all.reserveCapacity(n * n * n * 4)
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let l = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
            let y = l / Double(n - 1)
            let w = Float(0.5 + 2 * y * (1 - y))
            all.append(contentsOf: [w, w, w, 1])
        } } }
        return all.withUnsafeBufferPointer { Data(buffer: $0) }
    }()
}
