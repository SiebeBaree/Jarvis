import SwiftUI

// MARK: - Type scale (spec §B2) — suffixed "J" to avoid SwiftUI built-in clashes

public extension Font {
    /// 44 pt semibold rounded, monospaced digits — the daily score number.
    static let displayScore = Font.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit()

    /// 26 pt semibold — page titles.
    static let title1J = Font.system(size: 26, weight: .semibold)

    /// 20 pt semibold — card / sheet titles.
    static let title2J = Font.system(size: 20, weight: .semibold)

    /// 15 pt semibold — row titles, emphasized body.
    static let headlineJ = Font.system(size: 15, weight: .semibold)

    /// 15 pt regular — body text.
    static let bodyJ = Font.system(size: 15)

    /// 13 pt regular — secondary meta lines.
    static let subheadJ = Font.system(size: 13)

    /// 12 pt medium — pair with `SectionHeader` (uppercased, +0.6 tracking, textSecondary).
    static let captionJ = Font.system(size: 12, weight: .medium)

    /// 13 pt monospaced medium — stats, counts, fractions.
    static let monoJ = Font.system(size: 13, weight: .medium, design: .monospaced)
}

#Preview("Typography") {
    VStack(alignment: .leading, spacing: 12) {
        Text("84").font(.displayScore)
        Text("Title 1 — 26 semibold").font(.title1J)
        Text("Title 2 — 20 semibold").font(.title2J)
        Text("Headline — 15 semibold").font(.headlineJ)
        Text("Body — 15 regular, line height 22").font(.bodyJ)
        Text("Subhead — 13 regular").font(.subheadJ)
        Text("CAPTION — 12 MEDIUM").font(.captionJ).tracking(0.6)
        Text("mono 13 · 28/40").font(.monoJ)
    }
    .foregroundStyle(Color.textPrimary)
    .padding()
    .background(Color.bgCanvas)
}
