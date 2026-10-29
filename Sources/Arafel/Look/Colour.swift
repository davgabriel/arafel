import Foundation

/// A color in sRGB, gamma-encoded, 0-1.
struct RGB: Equatable, Codable {
    var r: Double, g: Double, b: Double

    var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    var linear: SIMD3<Double> {
        func decode(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return SIMD3(decode(r), decode(g), decode(b))
    }
}

extension RGB {
    /// For literals: traps on anything `init?(parsing:)` rejects.
    init(hex: String) { self.init(parsing: hex)! }

    /// Accepts "#C2410C", "c2410c" and "#F80"; nil for anything else.
    init?(parsing text: String) {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        // Rejects fullwidth digits (isHexDigit accepts them) and a leading + or - (UInt32(radix:) accepts it).
        guard t.count == 6, t.allSatisfy(\.isHexDigit), let v = UInt32(t, radix: 16) else { return nil }
        self.init(r: Double(v >> 16) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    /// Capped at 0-1: a blend in Oklab can land just outside sRGB.
    init(linear c: SIMD3<Double>) {
        func encode(_ x: Double) -> Double { min(1, max(0, x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055)) }
        self.init(r: encode(c.x), g: encode(c.y), b: encode(c.z))
    }
}

/// Oklab is perceptually even, so gradients through it don't go muddy in the middle.
enum Oklab {
    static func from(linear c: SIMD3<Double>) -> SIMD3<Double> {
        let l = cbrt(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z)
        let m = cbrt(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z)
        let s = cbrt(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z)
        return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func toLinear(_ c: SIMD3<Double>) -> SIMD3<Double> {
        let l = pow(c.x + 0.3963377774 * c.y + 0.2158037573 * c.z, 3)
        let m = pow(c.x - 0.1055613458 * c.y - 0.0638541728 * c.z, 3)
        let s = pow(c.x - 0.0894841775 * c.y - 1.2914855480 * c.z, 3)
        return SIMD3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                     -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                     -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }
}

/// A color along evenly spaced stops, blended in Oklab. p = 0 is the first stop, 1 the last. Linear RGB out.
func gradient(_ stops: [RGB], at p: Double) -> SIMD3<Double> {
    guard stops.count > 1 else { return stops.first?.linear ?? .zero }
    let x = min(1, max(0, p)) * Double(stops.count - 1)
    let i = min(stops.count - 2, Int(x)), f = x - Double(i)
    let a = Oklab.from(linear: stops[i].linear), b = Oklab.from(linear: stops[i + 1].linear)
    let c = Oklab.toLinear(a + (b - a) * f)
    return SIMD3(max(0, c.x), max(0, c.y), max(0, c.z))
}

/// Hue, saturation, brightness, all 0-1.
struct HSB {
    var h: Double, s: Double, b: Double

    init(_ c: RGB) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
        b = mx
        s = mx == 0 ? 0 : d / mx
        if d == 0 { h = 0 }
        else if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) / 6 }
        else if mx == c.g { h = ((c.b - c.r) / d + 2) / 6 }
        else { h = ((c.r - c.g) / d + 4) / 6 }
        if h < 0 { h += 1 }
    }

    var rgb: RGB {
        let x = (h >= 1 ? 0 : h) * 6, i = Int(x), f = x - Double(i)
        let p = b * (1 - s), q = b * (1 - s * f), t = b * (1 - s * (1 - f))
        switch i {
        case 0: return RGB(r: b, g: t, b: p)
        case 1: return RGB(r: q, g: b, b: p)
        case 2: return RGB(r: p, g: b, b: t)
        case 3: return RGB(r: p, g: q, b: b)
        case 4: return RGB(r: t, g: p, b: b)
        default: return RGB(r: b, g: p, b: q)
        }
    }
}
