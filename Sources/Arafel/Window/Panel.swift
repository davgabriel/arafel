import SwiftUI

struct Panel: View {
    @ObservedObject var studio: Studio
    @Environment(\.dg) private var dg

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button { studio.back() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(DGIconButton())
                    .keyboardShortcut(.cancelAction)
                    .help("Gallery")
                    .accessibilityLabel("Gallery")
                VStack(alignment: .leading, spacing: 2) {
                    Text(studio.photoName)
                        .font(DG.font(16, .semibold)).foregroundStyle(dg.ink).lineLimit(1).truncationMode(.middle)
                    // A space until the size is known, so the header keeps its height.
                    Text(studio.photoSize == .zero ? " " : "\(Int(studio.photoSize.width).formatted()) x \(Int(studio.photoSize.height).formatted())")
                        .font(DG.font(13.5)).monospacedDigit().foregroundStyle(dg.ink3)
                }
                Spacer(minLength: 0)
                Button { studio.deleteCommand() } label: { Image(systemName: "trash") }
                    .buttonStyle(DGIconButton(danger: true))
                    .help("Delete")
                    .accessibilityLabel("Delete")
            }
            .padding(.bottom, 22)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    section("Palette") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                            ForEach(Preset.all) { p in
                                Swatch(name: p.name, stops: p.stops, invert: studio.look.invert,
                                       selected: studio.look.presetID == p.id) {
                                    withAnimation(DG.spring) { studio.look.apply(p) }
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            ColourWell(label: "Near", value: studio.look.near, isOpen: picker("Near")) { studio.look.setNear($0) }
                            ColourWell(label: "Mid", value: studio.look.middle, isOpen: picker("Mid")) { studio.look.setMiddle($0) }
                            ColourWell(label: "Far", value: studio.look.far, isOpen: picker("Far")) { studio.look.setFar($0) }
                        }
                        .padding(.top, 4)
                        if studio.look.presetID == nil {
                            Text("Custom").font(DG.font(12.5, .medium)).foregroundStyle(dg.ink3)
                        }
                        Toggle("Invert", isOn: $studio.look.invert).toggleStyle(DGSwitch())
                    }
                    DGSlider(label: "Grain", value: $studio.look.grain)
                    DGSlider(label: "Softness", value: $studio.look.softness)
                    DGSlider(label: "See-through", value: $studio.look.show)
                }
                .padding(.bottom, 8)
            }
            .disabled(!studio.hasPhoto)
            .opacity(studio.hasPhoto ? 1 : 0.45)

            Spacer(minLength: 16)
            Button { studio.exportPanel() } label: {
                Label(exportLabel, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(DGButton(kind: .primary))
            .disabled(!studio.canExport)
        }
        .padding(24)
        .frame(width: 304)
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DG.radiusL))
    }

    private var exportLabel: String { studio.exporting ? "Exporting" : "Export" }

    /// One picker open at a time. Kept in Studio, which closes it on leaving the photo and on Invert.
    private func picker(_ name: String) -> Binding<Bool> {
        Binding(get: { studio.openWell == name }, set: { studio.openWell = $0 ? name : nil })
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(DG.font(12.5, .medium)).foregroundStyle(dg.ink3)
            content()
        }
    }
}

/// A preset's gradient, near on the left.
struct Swatch: View {
    let name: String
    let stops: [RGB]
    let invert: Bool
    let selected: Bool
    let action: () -> Void
    @Environment(\.dg) private var dg

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Capsule()
                    .fill(LinearGradient(stops: gradientStops, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 28)
                    .padding(3)
                    .overlay(Capsule().stroke(selected ? dg.ink : .clear, lineWidth: 2))
                Text(name).font(DG.font(12.5, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? dg.ink : dg.ink2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var gradientStops: [Gradient.Stop] {
        let s = invert ? stops.reversed() : stops
        return (0..<16).map { i in
            let p = Double(i) / 15
            return Gradient.Stop(color: RGB(linear: gradient(s, at: p)).color, location: p)
        }
    }
}
