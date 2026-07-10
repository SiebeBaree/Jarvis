import DesignSystem
import JarvisAPI
import SwiftUI

/// Universal score-band colors (§A8): gray <50, amber 50–69, green ≥70.
/// Replicates the small helper in Features/Plan/PlanDisplay — Reviews/Trends/
/// Body don't own that file, so they keep their own copy.
enum ScoreBands {
    static func color(_ value: Double?) -> Color {
        guard let value else { return .bgSubtle }
        if value < 50 { return .textTertiary }
        if value < 70 { return .warning }
        return .success
    }

    /// Mean of the non-nil totals; nil when nothing is scored.
    static func average(_ values: [Double?]) -> Double? {
        let scored = values.compactMap { $0 }
        guard !scored.isEmpty else { return nil }
        return scored.reduce(0, +) / Double(scored.count)
    }
}

/// "On track" / "At risk" / "Done" capsule for goal trackStatus strings.
/// Mirrors TrackStatusPill in Features/Plan (not owned by these features).
struct ReviewStatusPill: View {
    let status: String

    private var label: String? {
        switch status {
        case "on_track": "On track"
        case "at_risk": "At risk"
        case "done": "Done"
        default: nil
        }
    }

    private var color: Color {
        switch status {
        case "on_track": .success
        case "at_risk": .warning
        default: .textTertiary
        }
    }

    var body: some View {
        if let label {
            Text(label)
                .font(.captionJ)
                .foregroundStyle(color)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, 2)
                .background(color.opacity(0.12), in: Capsule())
        }
    }
}
