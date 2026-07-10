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

// MARK: - Design tokens (spec §B2)

public extension Color {
    // Backgrounds
    static let bgCanvas = dynamic(light: 0xFAFAF9, dark: 0x111113)
    static let bgSurface = dynamic(light: 0xFFFFFF, dark: 0x1A1A1D)
    static let bgSubtle = dynamic(light: 0xF4F4F3, dark: 0x232326)
    static let bgHover = dynamic(light: 0xF0F0EF, dark: 0x28282C)

    // Borders
    static let borderHairline = dynamic(light: 0xE7E7E5, dark: 0x2E2E33)
    static let borderStrong = dynamic(light: 0xD4D4D2, dark: 0x3D3D44)

    // Text
    static let textPrimary = dynamic(light: 0x18181B, dark: 0xF2F2F0)
    static let textSecondary = dynamic(light: 0x6E6E76, dark: 0x9E9EA7)
    static let textTertiary = dynamic(light: 0xA3A3AB, dark: 0x6B6B74)

    // Accent (restrained indigo — CTAs, selection, links, tasks arc only)
    static let accentPrimary = dynamic(light: 0x4F46E5, dark: 0x7C74F5)
    static let accentSubtle = dynamic(light: 0xEEEDFC, dark: 0x2A2843)

    // Semantic
    static let success = dynamic(light: 0x16A34A, dark: 0x4ADE80)
    static let successSubtle = dynamic(light: 0xE8F6EE, dark: 0x1C3226)
    static let warning = dynamic(light: 0xD97706, dark: 0xFBBF24)
    static let danger = dynamic(light: 0xDC2626, dark: 0xF87171)
}

// MARK: - Mood gradient (red → amber → green)

public extension LinearGradient {
    /// The 0–100 mood slider gradient.
    static var moodGradient: LinearGradient {
        LinearGradient(
            colors: [.danger, .warning, .success],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

#Preview("Colors") {
    let tokens: [(String, Color)] = [
        ("bgCanvas", .bgCanvas), ("bgSurface", .bgSurface), ("bgSubtle", .bgSubtle),
        ("bgHover", .bgHover), ("borderHairline", .borderHairline), ("borderStrong", .borderStrong),
        ("textPrimary", .textPrimary), ("textSecondary", .textSecondary), ("textTertiary", .textTertiary),
        ("accentPrimary", .accentPrimary), ("accentSubtle", .accentSubtle),
        ("success", .success), ("successSubtle", .successSubtle),
        ("warning", .warning), ("danger", .danger),
    ]
    return ScrollView {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tokens, id: \.0) { name, color in
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: 40, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.borderHairline))
                    Text(name).font(.caption)
                }
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient.moodGradient)
                .frame(height: 24)
        }
        .padding()
    }
    .background(Color.bgCanvas)
}
