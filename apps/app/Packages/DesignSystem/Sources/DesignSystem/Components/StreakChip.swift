import SwiftUI

// MARK: - Streak chip (spec §B5.4)
//
// Flame + mono count + unit ("12 days" / "6 weeks"). Hidden below 2
// (no "1 day streak" noise). Broken streaks show a grayed "ended" variant.

public struct StreakChip: View {
    private let count: Int
    private let unit: String
    private let ended: Bool

    public init(count: Int, unit: String, ended: Bool = false) {
        self.count = count
        self.unit = unit
        self.ended = ended
    }

    public var body: some View {
        if count >= 2 {
            HStack(spacing: Space.xs) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(ended ? Color.textTertiary : Color.warning)
                Text("\(count) \(unit)")
                    .font(.monoJ)
                    .foregroundStyle(ended ? Color.textTertiary : Color.textSecondary)
                if ended {
                    Text("ended")
                        .font(.captionJ)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 3)
            .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(ended ? "Streak of \(count) \(unit) ended" : "\(count) \(unit) streak"))
        }
    }
}

#Preview("StreakChip") {
    VStack(alignment: .leading, spacing: Space.lg) {
        StreakChip(count: 12, unit: "days")
        StreakChip(count: 6, unit: "weeks")
        StreakChip(count: 9, unit: "days", ended: true)
        HStack(spacing: Space.xs) {
            Text("count = 1 renders nothing →").font(.captionJ).foregroundStyle(Color.textTertiary)
            StreakChip(count: 1, unit: "days")
        }
    }
    .padding()
    .background(Color.bgCanvas)
}
