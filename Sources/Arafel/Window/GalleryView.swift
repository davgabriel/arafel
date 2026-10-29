import SwiftUI

struct GalleryView: View {
    @ObservedObject var studio: Studio
    @ObservedObject var library: Library
    @Environment(\.dg) private var dg

    var body: some View {
        VStack(spacing: 18) {
            header
            if library.works.isEmpty {
                empty.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 300), spacing: 16)], spacing: 16) {
                        ForEach(library.works) { work in
                            Tile(name: work.name, image: library.thumbs[work.id], selecting: studio.selecting,
                                 selected: studio.selection.contains(work.id)) {
                                if studio.selecting { studio.toggle(work.id) } else { studio.edit(work) }
                            } delete: {
                                studio.askDelete([work.id])
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.never)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo").font(.system(size: 24, weight: .regular)).foregroundStyle(dg.ink4).padding(.bottom, 4)
            Text("Drop a photo").font(DG.font(15, .medium)).foregroundStyle(dg.ink)
            Button { studio.openPanel() } label: { Text("Open") }
                .buttonStyle(DGButton(kind: .secondary)).frame(width: 120).padding(.top, 10)
        }
        .padding(.bottom, 60)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Arafel").font(DG.font(20, .semibold)).foregroundStyle(dg.ink)
            Spacer()
            if studio.selecting {
                Text(studio.selection.isEmpty ? "Select photos" : "\(studio.selection.count) selected")
                    .font(DG.font(14)).monospacedDigit().foregroundStyle(dg.ink3)
                    .padding(.trailing, 6)
                Button("Cancel") { withAnimation(DG.spring) { studio.selecting = false; studio.selection = [] } }
                    .buttonStyle(DGButton(kind: .secondary)).frame(width: 104)
                    .keyboardShortcut(.cancelAction)
                Button { studio.askDelete(studio.selection) } label: { Label("Delete", systemImage: "trash") }
                    .buttonStyle(DGButton(kind: .danger)).frame(width: 118)
                    .disabled(studio.selection.isEmpty)
            } else if !library.works.isEmpty {
                Button("Select") { withAnimation(DG.spring) { studio.selecting = true } }
                    .buttonStyle(DGButton(kind: .secondary)).frame(width: 104)
                Button { studio.openPanel() } label: { Label("Open", systemImage: "photo") }
                    .buttonStyle(DGButton(kind: .primary)).frame(width: 118)
            }
        }
        .frame(height: DG.controlHeight)
    }
}

private struct Tile: View {
    let name: String
    let image: CGImage?
    let selecting: Bool
    let selected: Bool
    let open: () -> Void
    let delete: () -> Void
    @Environment(\.dg) private var dg
    @StateObject private var hover = Held(false)

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFill()
                } else {
                    dg.surface2
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? dg.ink : .clear, lineWidth: 3))
            .overlay(alignment: .topTrailing) {
                if selecting {
                    ZStack {
                        Circle().fill(selected ? AnyShapeStyle(dg.ink) : AnyShapeStyle(.black.opacity(0.18)))
                        Circle().strokeBorder(.white, lineWidth: 2)
                        if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(dg.bg) }
                    }
                    .frame(width: 24, height: 24)
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: .black.opacity(dg.dark ? 0.45 : 0.14), radius: hover.value ? 18 : 10, y: hover.value ? 10 : 6)
            .scaleEffect(hover.value && !selecting ? 1.015 : 1)
            .animation(.easeOut(duration: 0.15), value: hover.value)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onHover { hover.value = $0 }
            .onTapGesture(perform: open)
            .contextMenu {
                Button(role: .destructive, action: delete) { Label("Delete", systemImage: "trash") }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, open)
    }
}
