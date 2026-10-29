import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var studio: Studio
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let dg = DG(dark: scheme == .dark)
        ZStack(alignment: .bottomTrailing) {
            DGPage()
            DropCatcher(targeted: { studio.dropTargeted = $0 }, dropped: { studio.open($0, temporary: $1, missing: $2) })
            Group {
                if studio.current == nil {
                    GalleryView(studio: studio, library: studio.library)
                        .overlay(alignment: .bottom) { notice.padding(.bottom, 4) }
                } else {
                    HStack(spacing: 20) {
                        canvas(dg)
                        Panel(studio: studio)
                    }
                }
            }
            // Drops land anywhere in the window, so the outline covers the gallery and the editor alike.
            .overlay(
                RoundedRectangle(cornerRadius: DG.radiusL)
                    .strokeBorder(dg.ink3.opacity(studio.dropTargeted ? 0.6 : 0), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(-10)
                    .animation(.easeOut(duration: 0.15), value: studio.dropTargeted)
                    .allowsHitTesting(false)
            )
            .padding(.top, 36)
            .padding([.leading, .trailing], 20)
            .padding(.bottom, 30)
            DGSignature().padding(.trailing, 6).padding(.bottom, 5)
        }
        .environment(\.dg, dg)
        .frame(minWidth: 980, minHeight: 680)
        .ignoresSafeArea()
        .onAppear { studio.undo = undoManager }
        .onChange(of: undoManager) { _, u in studio.undo = u }
        .confirmationDialog(deleteTitle, isPresented: Binding(
            get: { studio.pendingDelete != nil }, set: { if !$0 { studio.pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { studio.confirmDelete() }
            Button("Cancel", role: .cancel) { studio.pendingDelete = nil }
        }
    }

    private var deleteTitle: String {
        let n = studio.pendingDelete?.count ?? 1
        return n == 1 ? "Delete this photo?" : "Delete \(n) photos?"
    }

    @ViewBuilder private var notice: some View {
        if let n = studio.notice {
            DGNotice(kind: n.kind, text: n.text)
                .onTapGesture { studio.dismissNotice() }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func canvas(_ dg: DG) -> some View {
        GeometryReader { geo in
            ZStack {
                if let image = (studio.showOriginal ? studio.original : nil) ?? studio.preview {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .bottomLeading) {
                            if studio.phase == .ready { CompareButton(studio: studio) }
                        }
                        .shadow(color: .black.opacity(dg.dark ? 0.5 : 0.18), radius: 30, y: 16)
                        .opacity(studio.phase == .reading ? 0.35 : 1)
                        .animation(.easeOut(duration: 0.2), value: studio.phase)
                }
                switch studio.phase {
                case .reading: reading(dg)
                case .failed(let message): DGNotice(kind: .bad, text: message).frame(maxWidth: 420)
                case .ready, .empty: EmptyView()
                }
                VStack { Spacer(); notice.padding(.bottom, 12) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { studio.setCanvas(pixels(geo.size)) }
            .onChange(of: geo.size) { _, s in studio.setCanvas(pixels(s)) }
            .onChange(of: displayScale) { studio.setCanvas(pixels(geo.size)) }
        }
    }

    private func pixels(_ s: CGSize) -> CGSize { CGSize(width: s.width * displayScale, height: s.height * displayScale) }

    // Indeterminate: Core ML reports no progress.
    private func reading(_ dg: DG) -> some View {
        VStack(spacing: 12) {
            Text("Reading depth").font(DG.font(15, .medium)).foregroundStyle(dg.ink)
            Sweep().frame(width: 220, height: 10)
        }
        .padding(24)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DG.radiusL))
    }
}

/// Shows the original while held; Space does the same (Studio.watchSpace).
private struct CompareButton: View {
    @ObservedObject var studio: Studio
    @Environment(\.dg) private var dg

    var body: some View {
        Image(systemName: studio.showOriginal ? "eye.fill" : "eye")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(dg.ink)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !studio.showOriginal { studio.showOriginal = true } }
                .onEnded { _ in studio.showOriginal = false })
            .help("Original - hold Space")
            .accessibilityLabel("Show original")
            .padding(12)
    }
}

struct Sweep: View {
    @Environment(\.dg) private var dg

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(dg.track)
                .overlay(alignment: .leading) {
                    Capsule().fill(dg.liquid)
                        .frame(width: geo.size.width * 0.35)
                        .phaseAnimator([CGFloat(0), 0.65]) { bar, phase in
                            bar.offset(x: geo.size.width * phase)
                        } animation: { _ in .easeInOut(duration: 1.3) }
                }
                .clipShape(Capsule())
        }
    }
}
