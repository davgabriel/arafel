import CoreImage
import Foundation

/// Photo + depth + look -> artwork. Every size is a fraction of the short side and the grain is seeded per
/// photo, so a small preview matches the full-size export.
final class Renderer {
    /// Grain cells across the short side.
    static let grainCells: CGFloat = 750
    /// Softness at 100%: blur radius as a share of the short side.
    static let maxBlur: CGFloat = 0.012
    /// Grain at 100%: standard deviation of the noise cells, in sRGB values.
    static let maxGrain: Double = 0.10

    private var paletteKey = "", paletteData = Data()
    private var maskKey = "", maskData = Data()

    /// `photo` and `depth` must already be the same size, origin 0,0.
    func render(photo: CIImage, depth: CIImage, lo: Double, hi: Double, look: Look, seed: UInt64) -> CIImage {
        let extent = photo.extent
        let short = min(extent.width, extent.height)

        var image = depth.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": LUT.size, "inputCubeData": palette(look, lo, hi),
        ])

        if look.show > 0.005 {
            let mask = depth.applyingFilter("CIColorCube", parameters: [
                "inputCubeDimension": LUT.size, "inputCubeData": showMask(look.show, lo, hi),
            ])
            image = photo.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask,
            ])
        }

        let radius = look.softness * Self.maxBlur * short
        if radius > 0.3 {
            image = image.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: extent)
        }

        // Grain last, so the blur doesn't soften it.
        if look.grain > 0.005 {
            image = grain(on: image, amount: look.grain, extent: extent, seed: seed)
        }
        // Opaque like the exported JPEG, also where the photo is transparent.
        return image.cropped(to: extent).settingAlphaOne(in: extent)
    }

    /// Monochrome grain added in sRGB values: full strength in the mid-tones, half at black and white.
    private func grain(on image: CIImage, amount: Double, extent: CGRect, seed: UInt64) -> CIImage {
        let short = min(extent.width, extent.height), long = max(extent.width, extent.height)
        // Capped at 20 million cells (strips past about 35:1). Set by shape alone, so preview and export match.
        let scale = short / min(Self.grainCells, (20_000_000 * short / long).squareRoot())
        let grid = CGRect(x: -2, y: -2, width: ceil(extent.width / scale) + 4, height: ceil(extent.height / scale) + 4)
        let ox = CGFloat(seed % 8192), oy = CGFloat((seed / 8192) % 8192)

        // Sum of the three random channels, centered on 0 and the same in r, g and b.
        // CIRandomGenerator randomizes alpha too, which turns the grain into blotches; force it to 1 first.
        let k = CGFloat(2 * amount * Self.maxGrain)
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .transformed(by: CGAffineTransform(translationX: -ox, y: -oy))
            .cropped(to: grid)
            .settingAlphaOne(in: grid)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: k, z: k, w: 0), "inputGVector": CIVector(x: k, y: k, z: k, w: 0),
                "inputBVector": CIVector(x: k, y: k, z: k, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: -3 * k / 2, y: -3 * k / 2, z: -3 * k / 2, w: 0),
            ])
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
            .cropped(to: extent)

        let screen = image.applyingFilter("CILinearToSRGBToneCurve")
        let weight = screen.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": LUT.weightSize, "inputCubeData": LUT.grainWeight,
        ])
        let grain = noise.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: weight])
        // Addition doubles alpha; reset it.
        let sum = grain.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: screen])
            .settingAlphaOne(in: extent)
        // Clamp what the grain pushes past 0 or 1, but keep wide-gamut values that were outside already.
        let floor = screen.applyingFilter("CIMinimumCompositing", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .black).cropped(to: extent)])
        let ceiling = screen.applyingFilter("CIMaximumCompositing", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .white).cropped(to: extent)])
        return sum
            .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: floor])
            .applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: ceiling])
            .applyingFilter("CISRGBToneCurveToLinear")
            .cropped(to: extent)
    }

    private func palette(_ look: Look, _ lo: Double, _ hi: Double) -> Data {
        let key = "\(look.stops)|\(look.tone)|\(look.invert)|\(lo)|\(hi)"
        if key != paletteKey { paletteKey = key; paletteData = LUT.palette(look, lo: lo, hi: hi) }
        return paletteData
    }

    private func showMask(_ amount: Double, _ lo: Double, _ hi: Double) -> Data {
        let key = "\(amount)|\(lo)|\(hi)"
        if key != maskKey { maskKey = key; maskData = LUT.showMask(amount, lo: lo, hi: hi) }
        return maskData
    }

    /// FNV-1a of the photo's fingerprint, so preview and export get the same grain.
    static func seed(for key: String) -> UInt64 {
        key.utf8.reduce(1469598103934665603) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
}
