import CoreImage
import Foundation

/// A photo at full size, upright (EXIF orientation applied), with its origin at 0,0.
struct Photo {
    let url: URL
    let image: CIImage
    /// The export is written back in this space.
    let colorSpace: CGColorSpace

    var size: CGSize { image.extent.size }
    var name: String { url.deletingPathExtension().lastPathComponent }

    init(url: URL) throws {
        guard let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw PhotoError.unreadable(url.lastPathComponent)
        }
        self.url = url
        self.colorSpace = img.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        self.image = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
    }
}

enum PhotoError: LocalizedError {
    case unreadable(String)
    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "Can't open \(name)"
        }
    }
}
