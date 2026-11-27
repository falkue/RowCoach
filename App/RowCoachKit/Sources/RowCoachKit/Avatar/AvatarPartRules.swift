import Foundation

/// Welche 3D-Teile einer Figur sichtbar sind – die eine Regel für App (`RowerFigure`) und Vorschau
/// (tools/avatars/rig.py `figure_prims`, gleiche Reihenfolge und Schlüssel; geprüft mit
/// `tools/avatars/figure_parts_expected.json`, erzeugt von tools/avatars/export_rules.py).
///
/// Jedes Teil nennt den Prim-Namen der Generator-Teile (`<teil>__<gruppe>`), das Segment, an dem es hängt
/// (`pelvis`, `head`, `upperarm_R`, `forearm_L`, `thigh_R`, `shin_L`, `foot_R`, …), und den Farbschlüssel
/// (skin, hair, beard, shirt, shorts, socks, shoes, eyes, eyes_hl, headwear, cap, headband, sunglasses, watch).
/// Alles, was nicht in der Liste steht, ist aus.
public enum AvatarPartRules {
    public struct Part: Equatable, Hashable, Sendable, Codable {
        public var prim: String
        public var segment: String
        public var color: String

        public init(prim: String, segment: String, color: String) {
            self.prim = prim
            self.segment = segment
            self.color = color
        }
    }

    /// Form einer aufgelösten Erscheinung (nur die Felder, die über Teile entscheiden)
    public struct Shape: Equatable, Sendable, Codable {
        public var hairStyle: String
        public var shirtStyle: String
        public var legStyle: String
        public var beard: String
        public var accessories: [String]

        public init(hairStyle: String, shirtStyle: String, legStyle: String = "short", beard: String = "none",
                    accessories: [String] = []) {
            self.hairStyle = hairStyle
            self.shirtStyle = shirtStyle
            self.legStyle = legStyle
            self.beard = beard
            self.accessories = accessories
        }

        public init(_ r: AppearanceCatalog.Resolved) {
            self.init(hairStyle: r.hairStyle, shirtStyle: r.shirtStyle, legStyle: r.legStyle, beard: r.beard,
                      accessories: r.accessories)
        }
    }

    /// Frisuren, die unter der Cap als kurze Haarkappe erscheinen (lange Formen bleiben sichtbar)
    public static let capHair: Set<String> = ["short", "buzz", "curly", "afro", "headband", "cap"]

    public static func figureParts(_ s: Shape) -> [Part] {
        var acc = Set(s.accessories)
        if s.hairStyle == "cap" { acc.insert("cap") }
        if s.hairStyle == "headband" { acc.insert("headband") }
        let covered = acc.contains("hijab") || acc.contains("patka")
        var out: [Part] = []
        func add(_ prim: String, _ segment: String, _ color: String) {
            out.append(Part(prim: prim, segment: segment, color: color))
        }
        add("hips__shorts", "pelvis", "shorts")
        switch s.shirtStyle {
        case "tee", "longsleeve":
            add("torso_tee__shirt", "pelvis", "shirt")
        case "unisuit":
            add("torso_unisuit__skin", "pelvis", "skin")
            add("torso_unisuit__shirt", "pelvis", "shirt")
        default:
            add("torso_tank__skin", "pelvis", "skin")
            add("torso_tank__shirt", "pelvis", "shirt")
        }
        add("head__skin", "head", "skin")
        if !acc.contains("sunglasses") {
            add("eyes__eyes", "head", "eyes")
            add("eyes_white__eyes_hl", "head", "eyes_hl")
        }
        if s.hairStyle != "bald" && !covered {
            let h = acc.contains("cap") && capHair.contains(s.hairStyle) ? "cap" : s.hairStyle
            add("hair_\(h)__hair", "head", "hair")
        }
        if s.beard == "short" || s.beard == "full" {
            add("beard_\(s.beard)__hair", "head", "beard")
        }
        if acc.contains("hijab") {
            add("acc_hijab__headwear", "head", "headwear")
        } else if acc.contains("patka") {
            add("acc_patka__headwear", "head", "headwear")
        } else if acc.contains("cap") {
            add("acc_cap__accessory", "head", "cap")
        } else if acc.contains("headband") {
            add("acc_headband__accessory", "head", "headband")
        }
        if acc.contains("sunglasses") {
            add("acc_sunglasses__accessory", "head", "sunglasses")
        }
        let leg = s.legStyle == "long" ? "shorts" : "skin"
        for side in ["R", "L"] {
            switch s.shirtStyle {
            case "tee":
                add("upperarm_tee__shirt", "upperarm_\(side)", "shirt")
                add("upperarm_tee__skin", "upperarm_\(side)", "skin")
                add("forearm__skin", "forearm_\(side)", "skin")
            case "longsleeve":
                add("upperarm_bare__skin", "upperarm_\(side)", "shirt")
                add("forearm_long__shirt", "forearm_\(side)", "shirt")
                add("forearm_long__skin", "forearm_\(side)", "skin")
            default:
                add("upperarm_bare__skin", "upperarm_\(side)", "skin")
                add("forearm__skin", "forearm_\(side)", "skin")
            }
            add("thigh__shorts", "thigh_\(side)", "shorts")
            add("thigh__skin", "thigh_\(side)", leg)
            add("shin__skin", "shin_\(side)", leg)
            add("shin__socks", "shin_\(side)", "socks")
            add("foot__shoes", "foot_\(side)", "shoes")
        }
        if acc.contains("watch") {
            add("acc_watch__accessory", "forearm_L", "watch")
        }
        return out
    }
}
