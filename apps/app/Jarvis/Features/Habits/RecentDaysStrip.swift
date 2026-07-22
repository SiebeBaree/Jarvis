import DesignSystem
import JarvisAPI
import SwiftUI

/// TickTick-style trailing-7-days strip on a habit card: one tappable circle
/// per day so a forgotten day can be checked off up to a week later. The
/// server recomputes that day's score on backfill.
struct RecentDaysStrip: View {
    let entry: HabitTodayEntryDTO
    let recentDays: [HabitRecentDayDTO]
    let store: HabitsStore

    private var todayKey: DayKey { recentDays.last?.dayKey ?? DayKeyMath.todayKey() }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(recentDays) { day in
                dayCell(day)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Cell

    private func dayCell(_ day: HabitRecentDayDTO) -> some View {
        let habit = entry.habit
        let beforeStart = day.dayKey < habit.startDate
        let isToday = day.dayKey == todayKey
        let target = habit.type == .multiDaily ? habit.targetReps : 1
        let complete = day.reps >= target

        return VStack(spacing: 3) {
            Text(weekdayLetter(day.dayKey))
                .font(.captionJ)
                .foregroundStyle(isToday ? Color.accentPrimary : Color.textTertiary)

            ZStack {
                if complete {
                    Circle().fill(Color.success)
                    if habit.type == .multiDaily, habit.targetReps > 1 {
                        Text("\(day.reps)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    } else if habit.type == .weeklyFrequency, day.reps > 1 {
                        Text("\(day.reps)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else if day.reps > 0 {
                    // Partial multi-daily day: hollow ring + rep count.
                    Circle().strokeBorder(Color.success, lineWidth: 1.5)
                    Text("\(day.reps)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.success)
                } else {
                    Circle().strokeBorder(
                        beforeStart ? Color.borderHairline.opacity(0.4) : Color.borderHairline,
                        lineWidth: 1,
                    )
                }
            }
            .frame(width: 24, height: 24)
            .overlay {
                if isToday {
                    Circle()
                        .strokeBorder(Color.accentPrimary.opacity(0.5), lineWidth: 1)
                        .frame(width: 30, height: 30)
                }
            }
        }
        .contentShape(Rectangle())
        .opacity(beforeStart ? 0.35 : 1)
        .onTapGesture {
            guard !beforeStart else { return }
            tap(day)
        }
        .contextMenu {
            if !beforeStart {
                Button("Add one") {
                    Task { await store.logHabit(entry.habit.id, dayKey: dayKeyParam(day)) }
                }
                .disabled(habit.type != .weeklyFrequency && day.reps >= target)
                Button("Remove one") {
                    Task { await store.unlogHabit(entry.habit.id, dayKey: dayKeyParam(day)) }
                }
                .disabled(day.reps == 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(HabitDisplay.shortLabel(for: day.dayKey)): \(day.reps) logged")
        .accessibilityAddTraits(.isButton)
    }

    /// Tap = fill in the obvious next state: below target adds a rep, at
    /// target removes one (so a mis-tap is fixable with a second tap).
    private func tap(_ day: HabitRecentDayDTO) {
        let habit = entry.habit
        let target = habit.type == .multiDaily ? habit.targetReps : 1
        Task {
            if day.reps < target {
                await store.logHabit(habit.id, dayKey: dayKeyParam(day))
            } else {
                await store.unlogHabit(habit.id, dayKey: dayKeyParam(day))
            }
        }
    }

    /// The API treats a nil dayKey as today; pass the explicit key for
    /// past days only so today keeps the plain log path.
    private func dayKeyParam(_ day: HabitRecentDayDTO) -> DayKey? {
        day.dayKey == todayKey ? nil : day.dayKey
    }

    private func weekdayLetter(_ dayKey: DayKey) -> String {
        guard let date = DayKeyMath.date(from: dayKey) else { return "" }
        let symbol = date.formatted(.dateTime.weekday(.narrow))
        return symbol
    }
}
