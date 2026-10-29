import CoreImage
import Foundation

/// Model output at its own resolution: 0 = far, 1 = nearest. Data, so never color-managed.
struct DepthMap {
    let width: Int
    let height: Int
    let values: [Float16]
    /// 2nd and 98th percentiles. The renderer stretches between them so a few outliers can't flatten the rest.
    let lo: Double
    let hi: Double

    init(width: Int, height: Int, values: [Float16]) {
        self.width = width
        self.height = height
        self.values = values
        var bins = [Int](repeating: 0, count: 1024)
        for v in values { bins[min(1023, max(0, Int(Float(v) * 1023)))] += 1 }
        func percentile(_ p: Double) -> Double {
            let target = Int(Double(values.count) * p)
            var sum = 0
            for (i, n) in bins.enumerated() { sum += n; if sum >= target { return Double(i) / 1023 } }
            return 1
        }
        var lo = percentile(0.02), hi = percentile(0.98)
        if hi - lo < 0.05 { lo = 0; hi = 1 }   // nearly flat (a wall): don't stretch the noise
        self.lo = lo
        self.hi = hi
    }

    var image: CIImage {
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(bitmapData: data, bytesPerRow: width * 2, size: CGSize(width: width, height: height),
                       format: .Lh, colorSpace: nil)
    }

    func fitted(to size: CGSize) -> CIImage {
        image.resized(to: size)
    }
}

extension CIImage {
    /// Resized to an exact size, origin at 0,0. Lanczos when both sides shrink (no shimmer), else bilinear (no halos).
    func resized(to size: CGSize) -> CIImage {
        let sx = size.width / extent.width, sy = size.height / extent.height
        // Clamped, or both filters blend the transparent outside into the border pixels.
        let source = clampedToExtent()
        let out: CIImage
        if sx < 1 && sy < 1 {
            out = source.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: sy, kCIInputAspectRatioKey: sx / sy,
            ])
        } else {
            out = source.samplingLinear().transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }
        return out.cropped(to: CGRect(origin: .zero, size: size))
    }
}
