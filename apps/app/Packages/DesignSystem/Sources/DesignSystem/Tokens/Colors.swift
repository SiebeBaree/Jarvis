import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Hex + dynamic color helpers

public extension Color {
    /// Creates a color from a 24-bit RGB hex value, e.g. `Color(hex: 0x4F46E5)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Cross-platform dynamic color that resolves to `light` or `dark`
    /// based on the current appearance.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(Color(hex: dark)) : NSColor(Color(hex: light))
        })
        #else
        Color(hex: light)
        #endif
    }
}

// MARK: - Surfaces
//
// Three elevations instead of the old two. A card sits on the canvas; a
// control *inside* a card (a chip, a stepper, a filled field) needs a third
// step or it disappears into the card it sits on.

public extension Color {
    /// Page background.
    static let bgCanvas = dynamic(light: 0xF6F6F8, dark: 0x0E0E11)
    /// Cards, rows, sheets.
    static let bgSurface = dynamic(light: 0xFFFFFF, dark: 0x1A1A1F)
    /// Controls sitting on a surface; also the "empty" half of a track.
    static let bgSubtle = dynamic(light: 0xF1F1F4, dark: 0x25252B)
    /// Hover / pressed.
    static let bgHover = dynamic(light: 0xEAEAEE, dark: 0x2E2E35)

    // Borders. Hairlines carry much less of the design now that cards have
    // real elevation — these are for dividers and outlined states.
    static let borderHairline = dynamic(light: 0xE8E8EC, dark: 0x2A2A31)
    static let borderStrong = dynamic(light: 0xD5D5DC, dark: 0x3B3B45)

    // Text
    static let textPrimary = dynamic(light: 0x16161A, dark: 0xF4F4F6)
    static let textSecondary = dynamic(light: 0x6B6B78, dark: 0x9C9CAB)
    static let textTertiary = dynamic(light: 0xA0A0AF, dark: 0x6A6A78)

    // Accent
    static let accentPrimary = dynamic(light: 0x5B54E8, dark: 0x8B84FF)
    static let accentSubtle = dynamic(light: 0xEDECFD, dark: 0x272348)

    // Semantic
    static let success = dynamic(light: 0x16A34A, dark: 0x4ADE80)
    static let successSubtle = dynamic(light: 0xE6F7EE, dark: 0x14301F)
    static let warning = dynamic(light: 0xD97706, dark: 0xFBBF24)
    static let warningSubtle = dynamic(light: 0xFDF3E3, dark: 0x342409)
    static let danger = dynamic(light: 0xDC2626, dark: 0xF87171)
    static let dangerSubtle = dynamic(light: 0xFDECEC, dark: 0x371718)
}

// MARK: - Item palette
//
// Every habit, category and area gets a colour, and that colour is its
// identity everywhere it appears — icon tile, ring, calendar dots, charts.
// Colour is what makes a list of twelve habits scannable instead of a wall
// of identical gray rows, so it is a first-class token rather than a
// decoration.
//
// Stored as a stable `id` string so the server only ever round-trips a name;
// `ItemColor.named(_:)` falls back to indigo for anything unrecognised.

public struct ItemColor: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    private let light: UInt32
    private let dark: UInt32

    init(id: String, displayName: String, light: UInt32, dark: UInt32) {
        self.id = id
        self.displayName = displayName
        self.light = light
        self.dark = dark
    }

    /// The saturated colour — strokes, fills, icon glyphs, chart marks.
    public var color: Color { .dynamic(light: light, dark: dark) }

    /// The washed-out backing behind a glyph. Derived from `color` so a new
    /// palette entry needs one pair of hex values, not two.
    public var soft: Color { color.opacity(0.16) }

    /// Hex string as persisted by the API (`color_hex` columns).
    public var hexString: String { String(format: "#%06X", light) }
}

public extension ItemColor {
    static let indigo = ItemColor(id: "indigo", displayName: "Indigo", light: 0x5B54E8, dark: 0x8B84FF)
    static let violet = ItemColor(id: "violet", displayName: "Violet", light: 0x8B5CF6, dark: 0xA78BFA)
    static let blue = ItemColor(id: "blue", displayName: "Blue", light: 0x2F80ED, dark: 0x60A5FA)
    static let cyan = ItemColor(id: "cyan", displayName: "Cyan", light: 0x0891B2, dark: 0x22D3EE)
    static let teal = ItemColor(id: "teal", displayName: "Teal", light: 0x0D9488, dark: 0x2DD4BF)
    static let green = ItemColor(id: "green", displayName: "Green", light: 0x16A34A, dark: 0x4ADE80)
    static let lime = ItemColor(id: "lime", displayName: "Lime", light: 0x65A30D, dark: 0xA3E635)
    static let amber = ItemColor(id: "amber", displayName: "Amber", light: 0xD97706, dark: 0xFBBF24)
    static let orange = ItemColor(id: "orange", displayName: "Orange", light: 0xEA580C, dark: 0xFB923C)
    static let rose = ItemColor(id: "rose", displayName: "Rose", light: 0xE11D48, dark: 0xFB7185)
    static let pink = ItemColor(id: "pink", displayName: "Pink", light: 0xDB2777, dark: 0xF472B6)
    static let slate = ItemColor(id: "slate", displayName: "Slate", light: 0x64748B, dark: 0x94A3B8)

    /// Picker order. Deliberately starts on indigo (the app accent) so the
    /// default choice is the safe one.
    static let palette: [ItemColor] = [
        .indigo, .violet, .blue, .cyan, .teal, .green,
        .lime, .amber, .orange, .rose, .pink, .slate,
    ]

    /// Resolves a persisted value — either a palette id ("teal") or a hex
    /// string ("#0D9488") — back to a palette entry. Unknown values fall
    /// back to indigo rather than throwing, because a colour is cosmetic and
    /// must never be the reason a row fails to render.
    static func named(_ value: String?) -> ItemColor {
        guard let value, !value.isEmpty else { return .indigo }
        if let match = palette.first(where: { $0.id == value }) { return match }
        let normalized = value.hasPrefix("#") ? String(value.dropFirst()) : value
        if let match = palette.first(where: { $0.hexString.dropFirst().caseInsensitiveCompare(normalized) == .orderedSame }) {
            return match
        }
        return .indigo
    }

    /// Deterministic colour for something that has none yet, so a habit
    /// created before the picker existed still looks intentional.
    static func fallback(for seed: String) -> ItemColor {
        let hash = seed.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return palette[Int(hash % UInt32(palette.count))]
    }
}

// MARK: - Gradients

public extension LinearGradient {
    /// The 0–100 feel slider: red → amber → green.
    static var moodGradient: LinearGradient {
        LinearGradient(
            colors: [.danger, .warning, .success],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

public extension AngularGradient {
    /// The daily score arc. Violet into blue, sweeping clockwise from 12
    /// o'clock — the ring is the one place the app is allowed to be showy.
    static var scoreArc: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                .dynamic(light: 0x7C5CFF, dark: 0x9B85FF),
                .dynamic(light: 0x5B54E8, dark: 0x8B84FF),
                .dynamic(light: 0x2F80ED, dark: 0x60A5FA),
                .dynamic(light: 0x22B8CF, dark: 0x38D9E8),
            ]),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }
}

// MARK: - Elevation
//
// The old system banned shadows outright. Cards now float a little, which is
// what separates "a list of bordered boxes" from "an app". Kept very soft:
// two stacked shadows, the tight one for contact, the wide one for lift.

public extension View {
    func jarvisShadow(_ level: Elevation = .card) -> some View {
        shadow(color: level.tightColor, radius: level.tightRadius, y: level.tightY)
            .shadow(color: level.wideColor, radius: level.wideRadius, y: level.wideY)
    }
}

public enum Elevation: Sendable {
    /// Resting cards and rows.
    case card
    /// Lifted: a dragged row, an open composer, a popover.
    case raised
    /// Floating above everything: FAB, toast.
    case floating

    // Dark mode needs a heavier shadow to read at all against a near-black
    // canvas; light mode needs a lighter one or cards look grubby.
    var tightColor: Color {
        switch self {
        case .card: .dynamic(light: 0x1B1B2A, dark: 0x000000).opacity(0.05)
        case .raised: .dynamic(light: 0x1B1B2A, dark: 0x000000).opacity(0.07)
        case .floating: .dynamic(light: 0x1B1B2A, dark: 0x000000).opacity(0.10)
        }
    }

    var wideColor: Color {
        switch self {
        case .card: .dynamic(light: 0x1B1B2A, dark: 0x000000).opacity(0.06)
        case .raised: .dynamic(light: 0x1B1B2A, dark: 0x000000).opacity(0.12)
        case .floating: .dynamic(light: 0x1B1B2A, dark: 0x000000).opacity(0.20)
        }
    }

    var tightRadius: CGFloat {
        switch self {
        case .card: 1
        case .raised: 2
        case .floating: 3
        }
    }

    var wideRadius: CGFloat {
        switch self {
        case .card: 8
        case .raised: 16
        case .floating: 28
        }
    }

    var tightY: CGFloat { 1 }

    var wideY: CGFloat {
        switch self {
        case .card: 2
        case .raised: 6
        case .floating: 12
        }
    }
}

#Preview("Palette") {
    ScrollView {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Item palette").font(.title2J).foregroundStyle(Color.textPrimary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: Space.md) {
                ForEach(ItemColor.palette) { item in
                    VStack(spacing: Space.xs) {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(item.soft)
                            .frame(height: 40)
                            .overlay(Circle().fill(item.color).frame(width: 14, height: 14))
                        Text(item.displayName).font(.captionJ).foregroundStyle(Color.textSecondary)
                    }
                }
            }

            Text("Elevation").font(.title2J).foregroundStyle(Color.textPrimary)
            HStack(spacing: Space.lg) {
                ForEach([Elevation.card, .raised, .floating], id: \.wideRadius) { level in
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color.bgSurface)
                        .frame(height: 64)
                        .jarvisShadow(level)
                }
            }
        }
        .padding()
    }
    .background(Color.bgCanvas)
}
