import Foundation

/// A named palette, near to far, and the slider values it starts with.
struct Preset: Identifiable {
    let id: String
    let name: String
    let stops: [RGB]        // near -> far
    let tone: Double        // >1 pushes more of the picture toward the far color, <1 toward the near one
    let grain: Double
    let softness: Double
    let show: Double

    static let all: [Preset] = [
        Preset(id: "silver", name: "Silver", stops: ["#141414", "#E9E9E6"].map(RGB.init(hex:)),
               tone: 1.0, grain: 0.55, softness: 0.25, show: 0),
        Preset(id: "ember", name: "Ember", stops: ["#2A0A06", "#C2410C", "#F6E7D2"].map(RGB.init(hex:)),
               tone: 1.0, grain: 0.45, softness: 0.25, show: 0),
        Preset(id: "tide", name: "Tide", stops: ["#0B1F33", "#2F6F86", "#E3F1F2"].map(RGB.init(hex:)),
               tone: 1.0, grain: 0.45, softness: 0.25, show: 0),
        Preset(id: "bloom", name: "Bloom", stops: ["#3B0A2A", "#D9577A", "#FBE3D6"].map(RGB.init(hex:)),
               tone: 1.0, grain: 0.45, softness: 0.25, show: 0),
        Preset(id: "moss", name: "Moss", stops: ["#13200F", "#6E7F3A", "#ECEBD8"].map(RGB.init(hex:)),
               tone: 1.0, grain: 0.45, softness: 0.25, show: 0),
        Preset(id: "haze", name: "Haze", stops: ["#1C1630", "#7A6FA8", "#EDE9F5"].map(RGB.init(hex:)),
               tone: 1.0, grain: 0.45, softness: 0.25, show: 0),
    ]
}

/// Everything the renderer needs besides the photo and its depth. Sliders are 0-1.
struct Look: Equatable, Codable {
    var presetID: String?       // nil after a color is picked by hand ("Custom")
    var stops: [RGB]            // near -> far
    var tone: Double
    var invert = false
    var grain: Double
    var softness: Double
    var show: Double

    init(_ p: Preset) {
        presetID = p.id; stops = p.stops; tone = p.tone; grain = p.grain; softness = p.softness; show = p.show
    }

    static let start = Look(Preset.all[0])

    /// The colors actually shown near and far, after Invert.
    var near: RGB { invert ? stops.last! : stops.first! }
    var far: RGB { invert ? stops.first! : stops.last! }

    mutating func apply(_ p: Preset) {
        let keepInvert = invert
        self = Look(p)
        invert = keepInvert
    }

    /// The color halfway: a 3-color palette's middle stop, or the blend of a 2-color one, which a hand-picked
    /// middle then joins. Invert doesn't move it.
    var middle: RGB { stops.count == 3 ? stops[1] : RGB(linear: gradient(stops, at: 0.5)) }

    mutating func setNear(_ c: RGB) { set(c, at: invert ? stops.count - 1 : 0) }
    mutating func setFar(_ c: RGB) { set(c, at: invert ? 0 : stops.count - 1) }
    mutating func setMiddle(_ c: RGB) {
        if stops.count == 3 { return set(c, at: 1) }
        guard c.hex != middle.hex else { return }
        stops.insert(c, at: 1)
        presetID = nil
    }

    /// The same hex changes nothing, so a preset stays selected.
    private mutating func set(_ c: RGB, at i: Int) {
        guard c.hex != stops[i].hex else { return }
        stops[i] = c
        presetID = nil
    }
}
