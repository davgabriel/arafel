import AppKit
import Carbon.HIToolbox
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

/// Window state and the work behind it. Depth runs on one queue and previews on another, so a slider never
/// waits for the model. `current == nil` means the gallery is showing.
@MainActor
final class Studio: ObservableObject {
    enum Phase: Equatable { case empty, reading, ready, failed(String) }

    let library: Library
    @Published private(set) var current: Work?
    @Published private(set) var phase: Phase = .empty
    @Published var look = Look.start { didSet { lookChanged(from: oldValue) } }
    @Published private(set) var preview: CGImage?
    @Published private(set) var original: CGImage?        // the unedited photo at preview size, for compare
    @Published var showOriginal = false
    @Published private(set) var photoName = ""
    @Published private(set) var photoSize = CGSize.zero
    @Published private(set) var exporting = false
    @Published private(set) var notice: (kind: DGNotice.Kind, text: String)?
    @Published var dropTargeted = false
    @Published var openWell: String?                      // "Near", "Mid" or "Far" while its color picker is open
    @Published var selecting = false
    @Published var selection = Set<UUID>()
    @Published var pendingDelete: Set<UUID>?

    weak var undo: UndoManager? { didSet { library.undo = undo } }

    private var photo: Photo?
    private var depth: DepthMap?
    private var key = ""
    private var generation = 0

    private let depthQueue = DispatchQueue(label: "arafel.depth", qos: .userInitiated)
    private let renderQueue = DispatchQueue(label: "arafel.preview", qos: .userInteractive)
    nonisolated(unsafe) private var engine: DepthEngine?     // only touched on the depth queue
    private let worker = PreviewWorker()

    private var target = CGSize.zero      // preview size in pixels
    private var openedAt: TimeInterval = 0
    private var skippingClick = false
    private var rendering = false
    private var renderAgain = false
    private var noticeTask: Task<Void, Never>?

    // Saving and undo: a look change saves shortly after; a burst of changes is one undo step.
    private var placing = false           // setting look from a work or an undo, not from the user
    private var inBurst = false
    private var burstEnd: DispatchWorkItem?
    private var saveSoon: DispatchWorkItem?
    private var thumbSoon: DispatchWorkItem?

    init() {
        library = Library()
        library.willDelete = { [weak self] ids in self?.deleting(ids) }
        try? FileManager.default.removeItem(at: DropView.folder)
        // Load the model now (2-5 s) so the first photo doesn't wait for it.
        depthQueue.async { [self] in engine = try? DepthEngine() }
        watchSpace()
        watchClicks()
    }

    var hasPhoto: Bool { photo != nil && depth != nil }
    var canExport: Bool { current != nil && photo != nil && depth != nil && !exporting }

    // MARK: open, edit, back

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open([url]) }
    }

    /// Adds each photo to the library (or finds its work), opens the last one that worked, then shows what failed.
    /// `temporary`: files Photos wrote for us, deleted once copied. `missing`: promised files that never came.
    func open(_ urls: [URL], temporary: Bool = false, missing: [String] = []) {
        var opened: Work?
        var failed = missing.map { "Can't open \($0)" }
        for url in urls {
            do { opened = try library.add(url, keepsSource: !temporary) } catch { failed.append(error.localizedDescription) }
            if temporary { try? FileManager.default.removeItem(at: url) }
        }
        // Already open: editing it again would restore its last saved look over an unsaved change.
        if let opened, opened.id != current?.id { edit(opened) }
        if !failed.isEmpty { show(.bad, failed.count == 1 ? failed[0] : "Can't open \(failed.count) files", fade: false) }
    }

    func edit(_ work: Work) {
        leaveWork()
        current = work
        openedAt = ProcessInfo.processInfo.systemUptime
        selecting = false
        selection = []
        openWell = nil
        placing = true; look = work.look; placing = false
        load(work)
    }

    func back() {
        leaveWork()
        generation += 1
        current = nil
        photo = nil; depth = nil; preview = nil; original = nil
        phase = .empty
        showOriginal = false
        openWell = nil
        notice = nil
    }

    /// Saves what is pending for the open work, redraws its tile, and drops its look undo steps.
    private func leaveWork() {
        guard current != nil else { return }
        saveNow(wait: false)
        burstEnd?.cancel(); inBurst = false
        undo?.removeAllActions(withTarget: self)
    }

    /// Writes what the timers are still waiting on: the look and the tile's picture. With `wait` the picture is
    /// rendered before returning, for quit.
    func saveNow(wait: Bool = true) {
        guard let work = current else { return }
        saveSoon?.cancel(); saveSoon = nil
        library.update(work.id, look: look)
        if thumbSoon != nil { thumbSoon?.cancel(); thumbSoon = nil; makeThumb(wait: wait) }
    }

    /// Reads the photo and shows it plain right away; its depth comes from the depth queue.
    private func load(_ work: Work) {
        generation += 1
        let gen = generation, key = work.fingerprint
        phase = .reading
        notice = nil
        showOriginal = false
        depth = nil; preview = nil; original = nil
        photoName = work.fileName
        self.key = key
        let photo: Photo
        do { photo = try Photo(url: library.photoURL(work)) } catch {
            self.photo = nil
            photoSize = .zero
            phase = .failed(error.localizedDescription)
            return
        }
        self.photo = photo
        photoSize = photo.size
        showPlain()
        depthQueue.async { [self] in
            // Photos opened in a row queue up here. Skip any that is no longer open before the model runs.
            guard DispatchQueue.main.sync(execute: { gen == self.generation }) else { return }
            let result = Result { try self.depth(of: photo, key: key) }
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                switch result {
                case .success(let map):
                    self.depth = map
                    self.phase = .ready
                    self.schedulePreview()
                    self.scheduleThumb()
                case .failure(let error):
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// On the depth queue. A model that failed to load is tried again, so one downloaded while the app runs is
    /// picked up.
    nonisolated private func depth(of photo: Photo, key: String) throws -> DepthMap {
        if let kept = DepthStore.load(key) { return kept }
        if engine == nil { engine = try DepthEngine() }
        return try engine!.depth(of: photo, key: key)
    }

    /// Shows the plain photo while depth loads; it stays as the compare image.
    private func showPlain() {
        guard let photo, target != .zero else { return }      // the canvas hasn't reported its size yet
        let size = fit(photo.size), gen = generation
        renderQueue.async { [worker] in
            let cg = worker.plain(photo, size: size)
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                self.original = cg
                if self.depth == nil { self.preview = cg }
            }
        }
    }

    // MARK: look changes: preview, save, undo

    private func lookChanged(from old: Look) {
        guard look != old else { return }
        // An open picker holds the color it opened with, which Invert has moved to the other end.
        if look.invert != old.invert { openWell = nil }
        schedulePreview()
        guard current != nil else { return }
        scheduleSave()
        scheduleThumb()
        guard !placing else { return }
        // The first change of a burst records where it started; the burst ends after 0.6 s of quiet.
        if !inBurst { inBurst = true; registerLookUndo(back: old) }
        burstEnd?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.inBurst = false }
        burstEnd = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    private func registerLookUndo(back to: Look) {
        guard let undo, let id = current?.id else { return }
        undo.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated {
                guard s.current?.id == id else { return }
                s.burstEnd?.cancel(); s.inBurst = false
                let now = s.look
                s.placing = true; s.look = to; s.placing = false
                s.registerLookUndo(back: now)     // registered while undoing, so it becomes the redo
            }
        }
        undo.setActionName("Change")
    }

    private func scheduleSave() {
        saveSoon?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let id = self.current?.id else { return }
            self.saveSoon = nil
            self.library.update(id, look: self.look)
        }
        saveSoon = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func scheduleThumb() {
        thumbSoon?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.thumbSoon = nil; self?.makeThumb() }
        thumbSoon = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func makeThumb(wait: Bool = false) {
        guard let photo, let depth, let id = current?.id else { return }
        let s = min(1, Library.thumbShortSide / min(photo.size.width, photo.size.height))
        let size = CGSize(width: (photo.size.width * s).rounded(), height: (photo.size.height * s).rounded())
        let look = self.look, key = self.key
        let render = { [worker] in worker.render(photo, depth, key: key, look: look, size: size) }
        if wait {
            if let cg = renderQueue.sync(execute: render) { library.setThumb(cg, for: id) }
            return
        }
        renderQueue.async {
            guard let cg = render() else { return }
            DispatchQueue.main.async { self.library.setThumb(cg, for: id) }
        }
    }

    // MARK: preview

    /// Canvas size in pixels. Previews render at this size, never larger than the photo.
    func setCanvas(_ pixels: CGSize) {
        guard abs(pixels.width - target.width) > 2 || abs(pixels.height - target.height) > 2 else { return }
        target = pixels
        if depth == nil { showPlain() }
        schedulePreview()
    }

    private func fit(_ size: CGSize) -> CGSize {
        guard target.width > 0, target.height > 0 else { return size }
        let s = min(1, min(target.width / size.width, target.height / size.height))
        // At least 1 px each way, or a very thin photo rounds to nothing.
        return CGSize(width: max(1, (size.width * s).rounded()), height: max(1, (size.height * s).rounded()))
    }

    /// Latest wins: while one preview renders, further changes collapse into one more render.
    private func schedulePreview() {
        guard let photo, let depth, target != .zero else { return }
        if rendering { renderAgain = true; return }
        rendering = true
        let look = self.look, key = self.key, size = fit(photo.size), gen = generation
        // The compare image follows the canvas size too.
        let plainToo = original.map { CGSize(width: $0.width, height: $0.height) != size } ?? true
        renderQueue.async { [worker] in
            let cg = worker.render(photo, depth, key: key, look: look, size: size)
            let plain = plainToo ? worker.plain(photo, size: size) : nil
            DispatchQueue.main.async {
                self.rendering = false
                // Stale photo: drop the result, but still run the queued render.
                guard gen == self.generation else {
                    if self.renderAgain { self.renderAgain = false; self.schedulePreview() }
                    return
                }
                self.preview = cg
                if let plain { self.original = plain }
                if self.renderAgain { self.renderAgain = false; self.schedulePreview() }
            }
        }
    }

    // MARK: compare

    /// Hold Space to see the original, except while typing in a text field.
    private func watchSpace() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Space) else { return event }
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                // Release always ends compare, whatever modifiers are down by then.
                if event.type == .keyUp {
                    guard self.showOriginal else { return false }
                    self.showOriginal = false
                    return true
                }
                guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty, self.current != nil,
                      self.phase == .ready, !(NSApp.keyWindow?.firstResponder is NSText) else { return false }
                self.showOriginal = true
                return true
            }
            return swallow ? nil : event
        }
    }

    /// A tile opens on the first click of a double-click. Swallow the second, which would otherwise land on
    /// whatever editor control is now under the pointer.
    private func watchClicks() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            let down = event.type == .leftMouseDown, count = event.clickCount, time = event.timestamp
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                guard down else { defer { self.skippingClick = false }; return self.skippingClick }
                self.skippingClick = count > 1 && self.current != nil && time - self.openedAt < NSEvent.doubleClickInterval
                return self.skippingClick
            }
            return swallow ? nil : event
        }
    }

    // MARK: delete

    func askDelete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingDelete = ids
    }

    func deleteCommand() { askDelete(deleteTargets) }

    /// What Delete acts on: the open work in the editor, the selection in Select mode.
    var deleteTargets: Set<UUID> {
        if let c = current { return [c.id] }
        return selecting ? selection : []
    }

    func confirmDelete() {
        guard let ids = pendingDelete else { return }
        pendingDelete = nil
        library.delete(ids)
    }

    /// Runs before works are deleted, by Delete, Undo or Redo. Leaves the editor if its work is going (saving the
    /// look first, so Undo restores it), drops them from the selection, and ends Select mode if nothing is left.
    private func deleting(_ ids: Set<UUID>) {
        if let c = current, ids.contains(c.id) { back() }
        selection.subtract(ids)
        if library.works.allSatisfy({ ids.contains($0.id) }) { selecting = false }
    }

    func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    // MARK: export

    func exportPanel() {
        guard canExport, let work = current else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = Export.suggestedName(for: work.name)
        var isDir: ObjCBool = false
        if let src = work.source, FileManager.default.fileExists(atPath: src, isDirectory: &isDir), isDir.boolValue {
            panel.directoryURL = URL(fileURLWithPath: src, isDirectory: true)
        } else {
            panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        export(to: url)
    }

    /// Blocks until a running export is written, for quit. The preview queue is serial, so an empty sync job
    /// returns only after it.
    func finishExport() {
        if exporting { renderQueue.sync {} }
    }

    func export(to url: URL) {
        guard let photo, let depth, !exporting else { return }
        exporting = true
        let look = self.look, key = self.key
        renderQueue.async { [worker] in
            let result = Result { try worker.export(photo, depth, key: key, look: look, to: url) }
            DispatchQueue.main.async {
                self.exporting = false
                switch result {
                case .success: self.show(.ok, "Saved \(url.lastPathComponent)", fade: true)
                case .failure(let e): self.show(.bad, "Not saved - \(e.localizedDescription)", fade: false)
                }
            }
        }
    }

    func dismissNotice() {
        noticeTask?.cancel()
        withAnimation(DG.spring) { notice = nil }
    }

    func show(_ kind: DGNotice.Kind, _ text: String, fade: Bool) {
        noticeTask?.cancel()
        withAnimation(DG.spring) { notice = (kind, text) }
        guard fade else { return }
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { withAnimation(DG.spring) { self.notice = nil } }
        }
    }
}

/// Caches the photo and depth downsized to the sizes in use (preview, gallery tile), so a slider move
/// re-renders a small image. `@unchecked Sendable`: only ever used on the preview queue.
final class PreviewWorker: @unchecked Sendable {
    let context = CIContext(options: [.workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])
    let screen = CGColorSpace(name: CGColorSpace.displayP3)!
    let renderer = Renderer()
    private var photoKey = ""
    private var small: [String: (photo: CIImage, depth: CIImage)] = [:]

    func plain(_ photo: Photo, size: CGSize) -> CGImage? {
        context.createCGImage(photo.image.resized(to: size), from: CGRect(origin: .zero, size: size),
                              format: .RGBA8, colorSpace: screen)
    }

    func render(_ photo: Photo, _ depth: DepthMap, key: String, look: Look, size: CGSize) -> CGImage? {
        if key != photoKey { small = [:]; photoKey = key }
        let sk = "\(size.width)x\(size.height)"
        if small[sk] == nil {
            let rect = CGRect(origin: .zero, size: size)
            guard let p = context.createCGImage(photo.image.resized(to: size), from: rect, format: .RGBAh,
                                                colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
            else { return nil }
            if small.count >= 3 { small = [:] }           // a resized window leaves old sizes behind
            small[sk] = (CIImage(cgImage: p), depth.fitted(to: size))
        }
        let s = small[sk]!
        let art = renderer.render(photo: s.photo, depth: s.depth, lo: depth.lo, hi: depth.hi,
                                  look: look, seed: Renderer.seed(for: key))
        return context.createCGImage(art, from: art.extent, format: .RGBA8, colorSpace: screen)
    }

    func export(_ photo: Photo, _ depth: DepthMap, key: String, look: Look, to url: URL) throws {
        let art = Renderer().render(photo: photo.image, depth: depth.fitted(to: photo.size), lo: depth.lo, hi: depth.hi,
                                    look: look, seed: Renderer.seed(for: key))
        try Export.jpeg(art, to: url, colorSpace: photo.colorSpace, context: context)
    }
}
