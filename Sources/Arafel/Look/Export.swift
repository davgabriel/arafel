import CoreImage
import Foundation

/// Full-size JPEG in the photo's own color space (sRGB when that space isn't RGB).
enum Export {
    static let quality: CGFloat = 0.95

    static func jpeg(_ image: CIImage, to url: URL, colorSpace: CGColorSpace, context: CIContext) throws {
        let space = colorSpace.model == .rgb ? colorSpace : CGColorSpace(name: CGColorSpace.sRGB)!
        // An image blended with the photo carries its EXIF and GPS along; the file gets none of it.
        try context.writeJPEGRepresentation(of: image.settingProperties([:]), to: url, colorSpace: space, options: [
            kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality,
        ])
    }

    static func suggestedName(for name: String) -> String { "\(name)-arafel.jpg" }
}
