import SwiftUI

// MARK: - Type scale — suffixed "J" to avoid SwiftUI built-in clashes
//
// Rounded (SF Pro Rounded) for anything structural: titles, row names,
// numbers. Default SF Pro for running text, where rounded gets tiring to
// read. That split is what gives the app a friendly voice without turning
// paragraphs into a children's book.

public extension Font {
    /// 46 pt bold rounded, monospaced digits — the daily score.
    static let displayScore = Font.system(size: 46, weight: .bold, design: .rounded).monospacedDigit()

    /// 32 pt bold rounded — big stat numbers (streaks, totals).
    static let displayStat = Font.system(size: 32, weight: .bold, design: .rounded).monospacedDigit()

    /// 28 pt bold rounded — page titles.
    static let title1J = Font.system(size: 28, weight: .bold, design: .rounded)

    /// 20 pt semibold rounded — card and sheet titles.
    static let title2J = Font.system(size: 20, weight: .semibold, design: .rounded)

    /// 17 pt semibold rounded — section titles.
    static let title3J = Font.system(size: 17, weight: .semibold, design: .rounded)

    /// 16 pt semibold rounded — row titles. This is the app's workhorse.
    static let headlineJ = Font.system(size: 16, weight: .semibold, design: .rounded)

    /// 15 pt regular — body text.
    static let bodyJ = Font.system(size: 15)

    /// 13 pt regular — secondary meta lines.
    static let subheadJ = Font.system(size: 13)

    /// 13 pt medium rounded — meta lines that sit next to a headline.
    static let subheadStrongJ = Font.system(size: 13, weight: .medium, design: .rounded)

    /// 12 pt semibold rounded — section headers, chips.
    static let captionJ = Font.system(size: 12, weight: .semibold, design: .rounded)

    /// 11 pt medium rounded — the smallest legible label.
    static let microJ = Font.system(size: 11, weight: .medium, design: .rounded)

    /// 13 pt semibold rounded, monospaced digits — inline stats, fractions,
    /// counts. Rounded rather than SF Mono: mono read as "code" next to the
    /// rest of the type.
    static let monoJ = Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()

    /// 15 pt bold rounded, monospaced digits — numbers inside rings and pills.
    static let numeralJ = Font.system(size: 15, weight: .bold, design: .rounded).monospacedDigit()
}

#Preview("Typography") {
    VStack(alignment: .leading, spacing: 12) {
        Text("84").font(.displayScore)
        Text("12").font(.displayStat)
        Text("Title 1 — 28 bold rounded").font(.title1J)
        Text("Title 2 — 20 semibold rounded").font(.title2J)
        Text("Title 3 — 17 semibold rounded").font(.title3J)
        Text("Headline — 16 semibold rounded").font(.headlineJ)
        Text("Body — 15 regular").font(.bodyJ)
        Text("Subhead — 13 regular").font(.subheadJ)
        Text("Subhead strong — 13 medium").font(.subheadStrongJ)
        Text("CAPTION — 12 SEMIBOLD").font(.captionJ).tracking(0.5)
        Text("MICRO — 11 MEDIUM").font(.microJ)
        Text("28/40 · mono").font(.monoJ)
        Text("5").font(.numeralJ)
    }
    .foregroundStyle(Color.textPrimary)
    .padding()
    .background(Color.bgCanvas)
}
