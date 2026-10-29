import SwiftUI

/// Design tokens: light and dark colors, fonts, metrics.
struct DG {
    let dark: Bool

    private func c(_ day: UInt32, _ night: UInt32, _ dayA: Double = 1, _ nightA: Double = 1) -> Color {
        let v = dark ? night : day
        return Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255, opacity: dark ? nightA : dayA)
    }

    var bg: Color { c(0xF1F2F2, 0x111416) }
    var wash1: Color { c(0x828C92, 0xFFFFFF, 0.16, 0.05) }
    var wash2: Color { c(0x6E787E, 0xFFFFFF, 0.10, 0.03) }
    var surface2: Color { c(0x151A1C, 0x000000, 0.045, 0.25) }
    var knob: Color { c(0xFFFFFF, 0xEEF0F1) }
    var ink: Color { c(0x151A1C, 0xEEF0F1) }
    var ink2: Color { c(0x4A5154, 0xB6BCBF) }
    var ink3: Color { c(0x5E6569, 0x90979B) }
    var ink4: Color { c(0x9EA4A7, 0x5F666A) }
    var switchOff: Color { c(0x151A1C, 0xFFFFFF, 0.12, 0.14) }
    var track: Color { c(0x151A1C, 0xFFFFFF, 0.06, 0.07) }
    var accent: Color { c(0x22292E, 0xAAB4B9) }
    var accent2: Color { c(0x2D353A, 0xB7C0C4) }
    var accentInk: Color { c(0x151A1C, 0xEEF0F1) }
    var tint: Color { c(0x22292E, 0xFFFFFF, 0.08, 0.12) }
    var okSoft: Color { c(0xE3F3E9, 0x4CC38A, 0.78, 0.14) }
    var okInk: Color { c(0x146639, 0x86DCAE) }
    var badSoft: Color { c(0xFBE7E4, 0xEF6B5C, 0.8, 0.14) }
    var badInk: Color { c(0x8F2519, 0xF7A197) }

    var liquid: LinearGradient { LinearGradient(colors: [accent2, accent], startPoint: .top, endPoint: .bottom) }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Onest", size: size).weight(weight)
    }
    static func mono(_ size: CGFloat) -> Font { .custom("IBM Plex Mono", size: size) }

    static let controlHeight: CGFloat = 40
    static let radiusM: CGFloat = 14
    static let radiusL: CGFloat = 26
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.85)
}

private struct DGKey: EnvironmentKey { static let defaultValue = DG(dark: true) }
extension EnvironmentValues {
    var dg: DG { get { self[DGKey.self] } set { self[DGKey.self] = newValue } }
}

/// Background with two faint radial washes, so the glass has something to refract.
struct DGPage: View {
    @Environment(\.dg) private var dg
    var body: some View {
        GeometryReader { geo in
            ZStack {
                dg.bg
                RadialGradient(colors: [dg.wash1, .clear], center: UnitPoint(x: 0.12, y: -0.08),
                               startRadius: 0, endRadius: max(geo.size.width, 900) * 0.62)
                RadialGradient(colors: [dg.wash2, .clear], center: UnitPoint(x: 1.02, y: 1.08),
                               startRadius: 0, endRadius: max(geo.size.width, 760) * 0.6)
            }
        }
        .ignoresSafeArea()
    }
}

struct DGButton: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    let kind: Kind
    @Environment(\.dg) private var dg
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DG.font(14, kind == .secondary ? .medium : .semibold))
            .foregroundStyle(kind == .primary ? dg.accentInk : kind == .danger ? dg.badInk : dg.ink)
            .padding(.horizontal, 18)
            .frame(height: DG.controlHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
            .glassEffect(glass, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.45)
    }

    private var glass: Glass {
        switch kind {
        case .primary: .regular.tint(dg.tint).interactive()
        case .secondary: .regular.interactive()
        case .danger: .regular.tint(dg.badSoft).interactive()
        }
    }
}

struct DGIconButton: ButtonStyle {
    var danger = false
    @Environment(\.dg) private var dg
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(danger ? dg.badInk : dg.ink)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.45)
    }
}

struct DGSwitch: ToggleStyle {
    @Environment(\.dg) private var dg
    @GestureState private var pressed = false

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label.font(DG.font(14, .medium)).foregroundStyle(dg.ink)
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? AnyShapeStyle(dg.liquid) : AnyShapeStyle(dg.switchOff))
                Capsule().fill(dg.knob)
                    .frame(width: pressed ? 38 : 34, height: 24)
                    .shadow(color: .black.opacity(dg.dark ? 0.35 : 0.10), radius: 5, y: 2)
                    .padding(3)
            }
            .frame(width: 52, height: 30)
            .contentShape(Capsule())
            .onTapGesture { withAnimation(DG.spring) { configuration.isOn.toggle() } }
            .gesture(DragGesture(minimumDistance: 0).updating($pressed) { _, s, _ in s = true })
            .animation(DG.spring, value: pressed)
            .accessibilityAddTraits(.isToggle)
        }
    }
}

struct DGSlider: View {
    let label: String
    @Binding var value: Double
    @Environment(\.dg) private var dg
    @GestureState private var dragging = false
    @StateObject private var start = Held<Double?>(nil)     // the value a drag moves from

    private var shown: Int { Int((value * 100).rounded()) }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(label).font(DG.font(14, .medium)).foregroundStyle(dg.ink)
                Spacer()
                Text("\(shown)").font(DG.font(13.5)).monospacedDigit().foregroundStyle(dg.ink3)
            }
            GeometryReader { geo in
                let thumb: CGFloat = dragging ? 30 : 26
                let x = CGFloat(value) * (geo.size.width - thumb)
                ZStack(alignment: .leading) {
                    Capsule().fill(dg.track).frame(height: 8)
                        .overlay(Capsule().stroke(.black.opacity(dg.dark ? 0.25 : 0.05), lineWidth: 1).blur(radius: 0.5))
                    Capsule().fill(dg.liquid).frame(width: max(8, x + thumb / 2), height: 8)
                    Capsule().fill(dg.knob)
                        .frame(width: thumb, height: 20)
                        .shadow(color: .black.opacity(dg.dark ? 0.4 : 0.12), radius: 5, y: 2)
                        .offset(x: x)
                }
                .frame(height: 22)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($dragging) { _, dragging, _ in dragging = true }
                    .onChanged { g in
                        let track = geo.size.width - thumb
                        if start.value == nil {
                            // Pressed on the thumb: move from where it is. On the bare track: jump there.
                            let rest = CGFloat(value) * (geo.size.width - 26)
                            start.value = (rest...rest + 26).contains(g.startLocation.x)
                                ? value : min(1, max(0, Double((g.startLocation.x - thumb / 2) / track)))
                        }
                        let v = min(1, max(0, start.value! + Double(g.translation.width / track)))
                        if v != value { value = v }
                    })
                .onChange(of: dragging) { _, now in if !now { start.value = nil } }
                .animation(DG.spring, value: dragging)
            }
            .frame(height: 22)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(shown)")
        .accessibilityAdjustableAction { dir in
            value = min(1, max(0, value + (dir == .increment ? 0.05 : -0.05)))
        }
    }
}

struct DGNotice: View {
    enum Kind { case ok, bad }
    let kind: Kind
    let text: String
    @Environment(\.dg) private var dg

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: kind == .bad ? "exclamationmark.circle" : "checkmark.circle")
                .font(.system(size: 15, weight: .medium))
            Text(text).font(DG.font(14)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(kind == .bad ? dg.badInk : dg.okInk)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(kind == .bad ? dg.badSoft : dg.okSoft, in: RoundedRectangle(cornerRadius: DG.radiusM))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DG.radiusM))
    }
}

/// The ⌥ alone; a click shows who made the app.
struct DGSignature: View {
    @Environment(\.dg) private var dg
    @StateObject private var showing = Held(false)

    var body: some View {
        Button { showing.value = true } label: {
            Text("⌥")
                .font(DG.mono(12))
                .foregroundStyle(dg.ink.opacity(0.35))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About")
        .popover(isPresented: $showing.value, arrowEdge: .top) {
            VStack(spacing: 6) {
                Text("⌥").font(DG.mono(24))
                Text("Vibe-coded by David Gabriel").font(DG.font(13))
                Link("davidgabriel.net", destination: URL(string: "https://davidgabriel.net")!)
                    .font(DG.font(13))
                    .foregroundStyle(dg.ink3)
                    .pointerStyle(.link)
            }
            .foregroundStyle(dg.ink)
            .padding(20)
        }
    }
}
