import CryptoKit
import Foundation

/// Depth maps cached on disk, keyed by a hash of the photo file.
enum DepthStore {
    static var folder: URL { Library.base.appendingPathComponent("Depth", isDirectory: true) }

    static func fingerprint(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func load(_ key: String) -> DepthMap? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(key).depth")), data.count > 8 else { return nil }
        let w = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) })
        let h = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) })
        // A damaged file could hold any size; one this big would overflow the sum below.
        guard (1...16384).contains(w), (1...16384).contains(h), data.count == 8 + w * h * 2 else { return nil }
        let values = data.dropFirst(8).withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
        return DepthMap(width: w, height: h, values: values)
    }

    static func save(_ map: DepthMap, as key: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var data = Data()
        withUnsafeBytes(of: UInt32(map.width)) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(map.height)) { data.append(contentsOf: $0) }
        map.values.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        try? data.write(to: folder.appendingPathComponent("\(key).depth"), options: .atomic)
    }
}
