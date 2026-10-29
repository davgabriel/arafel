import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo in the gallery: its own copy of the file, its look, and a thumbnail.
struct Work: Identifiable, Codable {
    let id: UUID
    var fileName: String        // the original's name: shown, and names the export
    var photoFile: String       // the copy inside the work's folder
    var fingerprint: String     // DepthStore key; also spots a photo opened twice
    var source: String?         // the original's folder, where Export starts; nil for drops from Photos
    var added: Date
    var edited: Date
    var look: Look

    var name: String { (fileName as NSString).deletingPathExtension }
}

/// The gallery on disk: `Library/<id>/` holds `work.json`, the photo copy and `thumb.jpg`. Deleted works wait in
/// `Deleted/` so Undo can bring them back; the next launch removes them.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var works: [Work] = []          // last edited first
    @Published private(set) var thumbs: [UUID: CGImage] = [:]
    weak var undo: UndoManager?
    /// Called before works are deleted, whether by Delete or by Undo and Redo.
    var willDelete: ((Set<UUID>) -> Void)?

    let root: URL
    let bin: URL
    private let fm = FileManager.default

    /// `Application Support/Arafel`: the gallery and the cached depth.
    nonisolated static var base: URL {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Arafel", isDirectory: true)
    }

    init() {
        root = Library.base.appendingPathComponent("Library", isDirectory: true)
        bin = Library.base.appendingPathComponent("Deleted", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        load()
        purge()
    }

    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func photoURL(_ w: Work) -> URL { folder(w.id).appendingPathComponent(w.photoFile) }

    /// Returns the existing work for this photo, or copies it into a new one.
    func add(_ url: URL, keepsSource: Bool = true) throws -> Work {
        let original = url.resolvingSymlinksInPath()            // copyItem would copy a link as a link
        _ = try Photo(url: original)                              // throws for non-images before anything is copied
        let key = try DepthStore.fingerprint(of: original)
        if let w = works.first(where: { $0.fingerprint == key }) { return w }
        let id = UUID()
        let file = "photo." + (original.pathExtension.isEmpty ? "img" : original.pathExtension.lowercased())
        do {
            try fm.createDirectory(at: folder(id), withIntermediateDirectories: true)
            try fm.copyItem(at: original, to: folder(id).appendingPathComponent(file))
            let w = Work(id: id, fileName: url.lastPathComponent, photoFile: file, fingerprint: key,
                         source: keepsSource ? url.deletingLastPathComponent().path : nil,
                         added: .now, edited: .now, look: .start)
            try write(w)
            works.insert(w, at: 0)
            thumbs[id] = plainThumb(w)
            return w
        } catch {
            try? fm.removeItem(at: folder(id))
            throw error
        }
    }

    /// Saves the look and moves the work to the front.
    func update(_ id: UUID, look: Look) {
        guard let i = works.firstIndex(where: { $0.id == id }), works[i].look != look else { return }
        works[i].look = look
        works[i].edited = .now
        try? write(works[i])
        if i != 0 { works.insert(works.remove(at: i), at: 0) }
    }

    func setThumb(_ image: CGImage, for id: UUID) {
        guard works.contains(where: { $0.id == id }) else { return }
        thumbs[id] = image
        guard let dest = CGImageDestinationCreateWithURL(folder(id).appendingPathComponent("thumb.jpg") as CFURL,
                                                         UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    static let thumbShortSide: CGFloat = 480

    /// Moves works to `Deleted/`; Undo brings them back until the app quits.
    func delete(_ ids: Set<UUID>) {
        guard works.contains(where: { ids.contains($0.id) }) else { return }
        willDelete?(ids)
        let gone = works.filter { ids.contains($0.id) }
        try? fm.createDirectory(at: bin, withIntermediateDirectories: true)
        for w in gone {
            let dest = bin.appendingPathComponent(w.id.uuidString, isDirectory: true)
            try? fm.removeItem(at: dest)
            try? fm.moveItem(at: folder(w.id), to: dest)
            thumbs[w.id] = nil
        }
        works.removeAll { ids.contains($0.id) }
        undo?.registerUndo(withTarget: self) { lib in MainActor.assumeIsolated { lib.restore(gone) } }
        undo?.setActionName(Self.deleteTitle(gone.count))
    }

    private func restore(_ gone: [Work]) {
        // A photo added again since its delete keeps its new work; the old one stays in the bin.
        let live = Set(works.map(\.fingerprint))
        let back = gone.filter { !live.contains($0.fingerprint) }
        guard !back.isEmpty else { return }
        for w in back {
            try? fm.moveItem(at: bin.appendingPathComponent(w.id.uuidString, isDirectory: true), to: folder(w.id))
            thumbs[w.id] = loadThumb(w)
        }
        works = (works + back.filter { fm.fileExists(atPath: folder($0.id).path) }).sorted { $0.edited > $1.edited }
        let ids = Set(back.map(\.id))
        undo?.registerUndo(withTarget: self) { lib in MainActor.assumeIsolated { lib.delete(ids) } }
        undo?.setActionName(Self.deleteTitle(ids.count))
    }

    /// The menu and Undo name for deleting `count` works.
    nonisolated static func deleteTitle(_ count: Int) -> String { count == 1 ? "Delete Photo" : "Delete \(count) Photos" }

    /// Empties `Deleted/` at launch, with each photo's cached depth unless a kept work shares it.
    private func purge() {
        guard let items = try? fm.contentsOfDirectory(at: bin, includingPropertiesForKeys: nil) else { return }
        let kept = Set(works.map(\.fingerprint))
        for item in items {
            if let w = read(item.appendingPathComponent("work.json")), !kept.contains(w.fingerprint) {
                try? fm.removeItem(at: DepthStore.folder.appendingPathComponent("\(w.fingerprint).depth"))
            }
            try? fm.removeItem(at: item)
        }
    }

    private func load() {
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        works = dirs.compactMap { read($0.appendingPathComponent("work.json")) }
            .filter { fm.fileExists(atPath: photoURL($0).path) }
            .sorted { $0.edited > $1.edited }
        for w in works { thumbs[w.id] = loadThumb(w) }
    }

    func read(_ url: URL) -> Work? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Work.self, from: data)
    }

    private func write(_ w: Work) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(w).write(to: folder(w.id).appendingPathComponent("work.json"), options: .atomic)
    }

    private func loadThumb(_ w: Work) -> CGImage? {
        let url = folder(w.id).appendingPathComponent("thumb.jpg")
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return cg
        }
        return plainThumb(w)
    }

    /// Until the first render, the tile shows the photo.
    private func plainThumb(_ w: Work) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(photoURL(w) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat, let height = props[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0 else { return nil }
        // ImageIO limits the long side; tiles are sized by the short one.
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.thumbShortSide * max(width, height) / min(width, height),
        ] as CFDictionary)
    }
}
