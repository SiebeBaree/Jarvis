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

    /// The habit's own colour, so its strip, tile and control agree.
    private var tint: Color { HabitDisplay.color(for: entry.habit).color }

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
                .foregroundStyle(isToday ? Color.textPrimary : Color.textTertiary)

            ZStack {
                if complete {
                    Circle().fill(tint)
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
                    Circle().strokeBorder(tint, lineWidth: 1.5)
                    Text("\(day.reps)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tint)
                } else {
                    Circle().strokeBorder(
                        beforeStart ? Color.borderHairline.opacity(0.4) : Color.borderHairline,
                        lineWidth: 1,
                    )
                }
            }
            .frame(width: 24, height: 24)
            .jarvisAnimation(Motion.pop, value: day.reps)
            .overlay {
                if isToday {
                    Circle()
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 30, height: 30)
                }
            }
        }
        .contentShape(Rectangle())
        .opacity(beforeStart ? 0.35 : 1)
        .onTapGesture {
            guard !beforeStart else { return }
            Haptics.play(day.reps >= target ? .light : .success)
            tap(day)
        }
        .contextMenu {
            if !beforeStart {
                Button("Add one") {
                    store.logHabit(entry.habit.id, dayKey: dayKeyParam(day))
                }
                .disabled(habit.type != .weeklyFrequency && day.reps >= target)
                Button("Remove one") {
                    store.unlogHabit(entry.habit.id, dayKey: dayKeyParam(day))
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
                store.logHabit(habit.id, dayKey: dayKeyParam(day))
            } else {
                store.unlogHabit(habit.id, dayKey: dayKeyParam(day))
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
