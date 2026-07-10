import DesignSystem
import JarvisAPI
import SwiftUI

/// Today-screen slot (§B3): the weekly-review banner (Sunday 17:00 through
/// Monday), or the violet block-retrospective card during review week.
struct WeeklyReviewSlot: View {
    let payload: DayPayload

    var body: some View {
        if let block = payload.block {
            if payload.isReviewWeek {
                BlockRetroCard()
            } else if let pending = pendingReview {
                WeeklyReviewCard(
                    blockId: block.id,
                    weekNumber: pending.weekNumber,
                    isWrappingUp: pending.isWrappingUp,
                )
            }
        }
    }

    /// Sunday from 17:00 (late-night hours still belong to Sunday's dayKey)
    /// shows "Week N is wrapping up"; Monday shows "Week N−1 wrapped".
    private var pendingReview: (weekNumber: Int, isWrappingUp: Bool)? {
        guard let weekNumber = payload.weekNumber else { return nil }
        let weekday = HabitDisplay.weekdayIndex(of: payload.dayKey) // Mon = 1 … Sun = 7
        let hour = Calendar.current.component(.hour, from: .now)
        if weekday == 7, hour >= 17 || DayKeyMath.isLateNight() {
            return (weekNumber, true)
        }
        if weekday == 1 {
            return (max(weekNumber - 1, 1), false)
        }
        return nil
    }
}

// MARK: - Weekly review banner

private struct WeeklyReviewCard: View {
    let weekNumber: Int
    let isWrappingUp: Bool

    /// Per block+week "Skip this week" (no guilt copy, just gone).
    @AppStorage private var skipped: Bool
    @State private var showFlow = false

    init(blockId: String, weekNumber: Int, isWrappingUp: Bool) {
        self.weekNumber = weekNumber
        self.isWrappingUp = isWrappingUp
        _skipped = AppStorage(wrappedValue: false, "weeklyReviewSkipped.\(blockId).\(weekNumber)")
    }

    var body: some View {
        if !skipped {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekly review")
                            .font(.headlineJ)
                            .foregroundStyle(Color.textPrimary)
                        Text(isWrappingUp
                            ? "Week \(weekNumber) is wrapping up"
                            : "Week \(weekNumber) wrapped")
                            .font(.subheadJ)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: Space.sm)
                    Menu {
                        Button("Skip this week") { skipped = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Review options")
                }
                Button("Start review (~5 min)") { showFlow = true }
                    .buttonStyle(.jarvisPrimary)
                    .padding(.top, Space.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisCard()
            .reviewFlowCover(isPresented: $showFlow, kind: .weekly)
        }
    }
}

// MARK: - Block retrospective card (review week)

private struct BlockRetroCard: View {
    @State private var showFlow = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Block retrospective")
                .font(.headlineJ)
                .foregroundStyle(Color.accentPrimary)
            Text("Review week — close out this block")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
            Button("Start retrospective") { showFlow = true }
                .buttonStyle(.jarvisPrimary)
                .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .background(Color.accentSubtle.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.accentPrimary.opacity(0.35), lineWidth: 0.5),
        )
        .reviewFlowCover(isPresented: $showFlow, kind: .block)
    }
}
