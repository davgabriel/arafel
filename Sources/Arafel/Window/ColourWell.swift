import AppKit
import SwiftUI

/// A color well with its own popover picker; NSColorPanel opens wherever it was last left, often far away.
struct ColourWell: View {
    let label: String
    let value: RGB
    @Binding var isOpen: Bool
    let set: (RGB) -> Void
    @Environment(\.dg) private var dg

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 6) {
                // Three wells share the row: a label is never cut, the widest well takes the room it needs.
                Text(label).font(DG.font(13.5, .medium)).foregroundStyle(dg.ink2).fixedSize()
                Spacer(minLength: 0)
                Circle().fill(value.color)
                    .overlay(Circle().strokeBorder(dg.ink.opacity(0.18), lineWidth: 1))
                    .frame(width: 26, height: 26)
            }
            .padding(.leading, 12).padding(.trailing, 7)
            .frame(height: DG.controlHeight)
            .background(dg.surface2, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) color")
        .accessibilityValue(value.hex)
        // Below the well, so the picture stays in view.
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ColourPicker(start: value, set: set).environment(\.dg, dg)
        }
    }
}

/// Saturation-brightness field, hue bar, hex field and an eyedropper; every change applies at once.
struct ColourPicker: View {
    let set: (RGB) -> Void
    @StateObject private var hsb: Held<HSB>
    @StateObject private var hex: Held<String>
    @Environment(\.dg) private var dg

    private let width: CGFloat = 220
    private let height: CGFloat = 150

    init(start: RGB, set: @escaping (RGB) -> Void) {
        self.set = set
        _hsb = StateObject(wrappedValue: Held(HSB(start)))
        _hex = StateObject(wrappedValue: Held(start.hex))
    }

    var body: some View {
        VStack(spacing: 14) {
            field
            hueBar
            HStack(spacing: 8) {
                TextField("Hex", text: $hex.value)
                    .textFieldStyle(.plain)
                    .font(DG.mono(13))
                    .foregroundStyle(dg.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(dg.surface2, in: Capsule())
                    .onSubmit(typed)
                Button(action: sample) {
                    Image(systemName: "eyedropper").font(.system(size: 14, weight: .medium)).foregroundStyle(dg.ink2)
                        .frame(width: 34, height: 34)
                        .background(dg.surface2, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Pick from screen")
                .accessibilityLabel("Pick from screen")
            }
        }
        .padding(16)
        .frame(width: width + 32)
    }

    private var field: some View {
        ZStack {
            Rectangle().fill(Color(hue: hsb.value.h, saturation: 1, brightness: 1))
            Rectangle().fill(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing))
            Rectangle().fill(LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topLeading) {
            thumb(hsb.value.rgb.color).position(x: hsb.value.s * width, y: (1 - hsb.value.b) * height)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            hsb.value.s = clamp(g.location.x / width)
            hsb.value.b = 1 - clamp(g.location.y / height)
            commit()
        })
    }

    private var hueBar: some View {
        Capsule()
            .fill(LinearGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) },
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: 14)
            .overlay(alignment: .topLeading) {
                thumb(Color(hue: hsb.value.h, saturation: 1, brightness: 1)).position(x: hsb.value.h * width, y: 7)
            }
            .contentShape(Rectangle().inset(by: -6))
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                hsb.value.h = min(clamp(g.location.x / width), 0.9999)
                commit()
            })
    }

    private func thumb(_ fill: Color) -> some View {
        Circle().fill(fill)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .frame(width: 18, height: 18)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .allowsHitTesting(false)
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    private func commit() {
        let c = hsb.value.rgb
        hex.value = c.hex
        set(c)
    }

    /// Applies typed hex on Return; anything invalid reverts to the last good color.
    private func typed() {
        guard let c = RGB(parsing: hex.value) else { hex.value = hsb.value.rgb.hex; return }
        let keepHue = hsb.value.h
        hsb.value = HSB(c)
        if hsb.value.s == 0 { hsb.value.h = keepHue }
        hex.value = c.hex
        set(c)
    }

    private func sample() {
        NSColorSampler().show { picked in
            guard let s = picked?.usingColorSpace(.sRGB) else { return }
            let c = RGB(r: Double(s.redComponent), g: Double(s.greenComponent), b: Double(s.blueComponent))
            DispatchQueue.main.async {
                hsb.value = HSB(c)
                hex.value = c.hex
                set(c)
            }
        }
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}
