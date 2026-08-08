import SwiftUI

// MARK: - Streak chip
//
// Flame + count. Hidden below 2 — a "1 day streak" is not a streak, it is
// noise on every freshly created habit. Broken streaks grey out rather than
// alarming: this app never punishes.

public struct StreakChip: View {
    private let count: Int
    private let unit: String
    private let ended: Bool
    private let isCompact: Bool

    public init(count: Int, unit: String, ended: Bool = false, compact: Bool = false) {
        self.count = count
        self.unit = unit
        self.ended = ended
        self.isCompact = compact
    }

    private var tint: Color { ended ? .textTertiary : .warning }

    public var body: some View {
        if count >= 2 {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: isCompact ? 9 : 10, weight: .semibold))
                Text(isCompact ? "\(count)" : "\(count) \(unit)")
                    .font(.microJ)
                    .monospacedDigit()
                if ended, !isCompact {
                    Text("ended").font(.microJ).opacity(0.7)
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, isCompact ? 5 : Space.sm)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
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
        StreakChip(count: 24, unit: "days", compact: true)
        HStack(spacing: Space.xs) {
            Text("count = 1 renders nothing →").font(.subheadJ).foregroundStyle(Color.textTertiary)
            StreakChip(count: 1, unit: "days")
        }
    }
    .padding()
    .background(Color.bgCanvas)
}
