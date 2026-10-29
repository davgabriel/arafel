import CoreImage
import CoreML
import Foundation
import Vision

/// Apple Depth Pro via Core ML: a 1536 x 1536 image in, inverse depth out (1 = nearest).
final class DepthEngine {
    static let modelName = "DepthProNormalizedInverseDepth"

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Arafel/Models", isDirectory: true)
    }
    static var packageURL: URL { folder.appendingPathComponent("\(modelName).mlpackage") }
    static var compiledURL: URL { folder.appendingPathComponent("\(modelName).mlmodelc") }

    static let weightBytes = 1_293_014_720   // weight.bin, as scripts/get-model.sh downloads it

    static var isCompiled: Bool { FileManager.default.fileExists(atPath: compiledURL.path) }

    /// SwiftPM can't compile an .mlpackage at build time, so the first launch does.
    static func compile() throws {
        let fm = FileManager.default
        // A partial download compiles without complaint and only fails to load, so check the weights first.
        let weights = packageURL.appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin")
        guard (try? fm.attributesOfItem(atPath: weights.path))?[.size] as? Int == weightBytes else {
            throw EngineError.modelMissing
        }
        guard let temp = try? MLModel.compileModel(at: packageURL) else { throw EngineError.modelDamaged }
        try? fm.removeItem(at: compiledURL)
        try fm.moveItem(at: temp, to: compiledURL)
    }

    private let model: MLModel
    private let constraint: MLImageConstraint
    private let context = CIContext(options: [.workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])

    init() throws {
        let config = MLModelConfiguration()
        // No Neural Engine: 6.6 s a photo on an M3, vs 7.2 s with it allowed and 9.3 s on it alone.
        config.computeUnits = .cpuAndGPU
        if !Self.isCompiled { try Self.compile() }
        var loaded = try? MLModel(contentsOf: Self.compiledURL, configuration: config)
        if loaded == nil {
            // A copy compiled from a partial download fails here. Rebuild it from the package once.
            try? FileManager.default.removeItem(at: Self.compiledURL)
            try Self.compile()
            loaded = try? MLModel(contentsOf: Self.compiledURL, configuration: config)
        }
        guard let loaded else { throw EngineError.modelDamaged }
        model = loaded
        guard let c = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else {
            throw EngineError.unexpectedModel
        }
        constraint = c
    }

    /// Depth at the model's resolution. The photo is squashed into the square; `DepthMap.fitted(to:)` undoes it.
    private func depth(of photo: Photo) throws -> DepthMap {
        guard let cg = context.createCGImage(photo.image, from: photo.image.extent) else { throw EngineError.noInput }
        let input = try MLFeatureValue(cgImage: cg, constraint: constraint,
                                       options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
        let provider = try MLDictionaryFeatureProvider(dictionary: ["image": input])
        let out = try model.prediction(from: provider)
        guard let buffer = out.featureValue(for: "normalizedInverseDepth")?.imageBufferValue,
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent16Half
        else { throw EngineError.noOutput }
        // Values arrive as 0-255, not the 0-1 the model card says.
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw EngineError.noOutput }
        var values = [Float16](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float16.self)
            for x in 0..<w { values[y * w + x] = Float16(min(1, max(0, Float(row[x]) / 255))) }
        }
        return DepthMap(width: w, height: h, values: values)
    }

    /// Runs the model and saves the result under `key`. Callers check `DepthStore` first.
    func depth(of photo: Photo, key: String) throws -> DepthMap {
        let map = try depth(of: photo)
        DepthStore.save(map, as: key)
        return map
    }
}

enum EngineError: LocalizedError {
    case modelMissing, modelDamaged, unexpectedModel, noInput, noOutput
    var errorDescription: String? {
        switch self {
        case .modelMissing: return "Depth model missing"   // scripts/get-model.sh
        case .modelDamaged: return "Depth model damaged"
        case .unexpectedModel: return "Depth model not recognized"
        case .noInput, .noOutput: return "No depth for this photo"
        }
    }
}
