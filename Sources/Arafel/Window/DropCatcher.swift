import AppKit
import SwiftUI

/// Window-wide drop target. AppKit rather than SwiftUI's drop handling, which takes files but not the file
/// promises Photos sends.
struct DropCatcher: NSViewRepresentable {
    let targeted: (Bool) -> Void
    /// (files, temporary, missing): `temporary` for promised files written into a scratch folder, `missing` for
    /// the names of promised files that never arrived.
    let dropped: ([URL], Bool, [String]) -> Void

    func makeNSView(context: Context) -> DropView { DropView(targeted: targeted, dropped: dropped) }
    func updateNSView(_ view: DropView, context: Context) { view.targeted = targeted; view.dropped = dropped }
}

final class DropView: NSView {
    var targeted: (Bool) -> Void
    var dropped: ([URL], Bool, [String]) -> Void
    private let queue = OperationQueue()

    /// Promised files land here, a folder per drop. Emptied at launch rather than per drop, because a drop's later
    /// files may still be arriving when the first is handled.
    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Arafel-drops", isDirectory: true)

    init(targeted: @escaping (Bool) -> Void, dropped: @escaping ([URL], Bool, [String]) -> Void) {
        self.targeted = targeted
        self.dropped = dropped
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Behind everything: a mouse-down that reaches it can still move the window.
    override var mouseDownCanMoveWindow: Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard Self.hasPhotos(sender.draggingPasteboard) else { return [] }
        targeted(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { targeted(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { targeted(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        targeted(false)
        return Self.receive(from: sender.draggingPasteboard, queue: queue, dropped: dropped)
    }

    static func hasPhotos(_ pb: NSPasteboard) -> Bool {
        pb.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
            || pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    /// Plain files are handed over at once, as one list. Promised files are written into a fresh folder and handed
    /// over together once each promise has answered.
    static func receive(from pb: NSPasteboard, queue: OperationQueue, dropped: @escaping ([URL], Bool, [String]) -> Void) -> Bool {
        guard let items = pb.readObjects(forClasses: [NSFilePromiseReceiver.self, NSURL.self],
                                         options: [.urlReadingFileURLsOnly: true]), !items.isEmpty else { return false }
        let files = items.compactMap { $0 as? URL }
        if !files.isEmpty { dropped(files, false, []) }
        let promises = items.compactMap { $0 as? NSFilePromiseReceiver }
        guard !promises.isEmpty else { return true }
        let into = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: into, withIntermediateDirectories: true)
        let arrivals = Arrivals(expecting: promises.count, done: dropped)
        for promise in promises {
            promise.receivePromisedFiles(atDestination: into, options: [:], operationQueue: queue) { url, error in
                DispatchQueue.main.async { arrivals.arrived(url, error) }
            }
        }
        return true
    }
}

/// The promised files of one drop, collected on the main thread and handed over together once every promise has
/// answered, with the names of any that failed. Files a promise delivers after that come one by one.
final class Arrivals {
    private var files: [URL] = []
    private var missing: [String] = []
    private var waiting: Int
    private let done: ([URL], Bool, [String]) -> Void

    init(expecting promises: Int, done: @escaping ([URL], Bool, [String]) -> Void) {
        waiting = promises
        self.done = done
    }

    func arrived(_ url: URL, _ error: Error?) {
        if error == nil { files.append(url) } else { missing.append(url.lastPathComponent) }
        waiting -= 1
        guard waiting <= 0 else { return }
        done(files, true, missing)
        files = []
        missing = []
    }
}
