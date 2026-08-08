import DesignSystem
import JarvisAPI
import SwiftUI

/// The habit row, shared by Today and the Habits tab.
///
/// One row, one tap. The control on the right is the whole interaction: a
/// check for daily habits, a count ring for everything counted. Both are 44 pt
/// targets, both animate, both fire a haptic — logging a habit is the thing
/// this app is for, so it is the thing that got the most attention.
///
/// Previously Today and Habits each drew their own version of this with
/// different controls, different spacing and different colours, which is a
/// large part of why the app read as several apps stapled together.
struct HabitRow: View {
    let entry: HabitTodayEntryDTO
    /// The dayKey this row logs into — Today's pager can be showing a past day.
    var dayKey: DayKey
    /// Weekly habits that are not planned today sit in a quieter group.
    var isMuted: Bool = false
    var showsPace: Bool = true
    /// Current streak, when the caller has stats loaded. Today's payload does
    /// not carry one, so the row simply omits it there rather than firing a
    /// per-habit stats request to decorate a caption.
    var streak: StreakDTO? = nil
    var onLog: () -> Void
    var onUnlog: () -> Void
    var onOpen: (() -> Void)?

    private var habit: HabitDTO { entry.habit }
    private var color: ItemColor { HabitDisplay.color(for: habit) }

    private var isSatisfied: Bool {
        switch habit.type {
        case .daily, .multiDaily: entry.repsToday >= habit.targetReps
        case .weeklyFrequency: entry.weekTotal >= habit.targetReps
        }
    }

    var body: some View {
        HStack(spacing: Space.md) {
            IconTile(symbol: HabitDisplay.icon(for: habit), color: color, isMuted: isMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.headlineJ)
                    .foregroundStyle(isMuted ? Color.textSecondary : Color.textPrimary)
                    .lineLimit(1)
                subtitle
            }

            Spacer(minLength: Space.sm)

            control
        }
        .padding(.vertical, Space.sm)
        .frame(minHeight: RowHeight.standard)
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
        .contextMenu {
            if let onOpen {
                Button("Open habit", systemImage: "chart.bar") { onOpen() }
            }
            Button("Undo last", systemImage: "arrow.uturn.backward") { onUnlog() }
                .disabled(entry.repsToday == 0)
        }
        .accessibilityElement(children: .contain)
    }

    /// Weekly habits get the pace bar; everything else gets a one-line caption.
    /// The pace bar is the only subtitle that carries information you cannot
    /// already see in the control, so it is the only one that gets two lines.
    @ViewBuilder
    private var subtitle: some View {
        if habit.type == .weeklyFrequency, showsPace {
            PaceCapsule(
                target: habit.targetReps,
                done: entry.weekTotal,
                expectedByTonight: HabitDisplay.expectedByTonight(
                    target: habit.targetReps,
                    dayKey: dayKey,
                ),
                status: HabitDisplay.paceStatus(entry.pace),
                tint: color.color,
            )
            .frame(maxWidth: 170, alignment: .leading)
        } else {
            HStack(spacing: Space.sm) {
                Text(HabitDisplay.typeCaption(for: habit))
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
                if let streak {
                    StreakChip(count: streak.current, unit: streak.unit, compact: true)
                }
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch habit.type {
        case .daily:
            CheckCircle(isOn: entry.repsToday > 0, tint: color.color, size: 28) {
                if entry.repsToday > 0 { onUnlog() } else { onLog() }
            }

        case .multiDaily:
            CountRing(
                done: entry.repsToday,
                target: habit.targetReps,
                tint: color.color,
                action: entry.repsToday >= habit.targetReps ? nil : onLog,
            )
            // Tapping a finished counter should undo, not sit inert.
            .overlay {
                if entry.repsToday >= habit.targetReps {
                    Button(action: onUnlog) { Color.clear }
                        .buttonStyle(.plain)
                        .frame(width: RowHeight.tapTarget, height: RowHeight.tapTarget)
                        .contentShape(Circle())
                        .accessibilityLabel("Undo one")
                }
            }

        case .weeklyFrequency:
            CountRing(
                done: entry.weekTotal,
                target: habit.targetReps,
                tint: color.color,
                action: onLog,
            )
        }
    }

    /// Exposed so callers can mirror the row's own idea of "done" (e.g. for
    /// sorting completed habits to the bottom).
    var satisfied: Bool { isSatisfied }
}
