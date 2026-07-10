import DesignSystem
import Foundation
import JarvisAPI

/// Navigation route to a habit's detail screen (pushed from Today and Habits).
struct HabitDetailRoute: Hashable, Identifiable {
    let habitId: String
    var id: String { habitId }
}

/// Shared display logic for habits (pace mapping, captions, week math).
/// Mirrors the server's display rule (§A8): elapsed excludes today before
/// 18:00 so the app never calls you "behind" at 7 AM.
enum HabitDisplay {
    static func icon(for habit: HabitDTO) -> String {
        let name = habit.icon?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "circle" : name
    }

    static func typeCaption(for habit: HabitDTO) -> String {
        switch habit.type {
        case .daily: "Daily"
        case .multiDaily: "\(habit.targetReps)×/day"
        case .weeklyFrequency: "Weekly · \(habit.targetReps)×/wk"
        }
    }

    /// Maps the server pace DTO onto the DesignSystem display status.
    static func paceStatus(_ pace: PaceDTO?) -> PaceDisplayStatus {
        switch pace?.kind {
        case "week_done": .weekDone
        case "behind": .behind(max(pace?.by ?? 1, 1))
        case "out_of_reach": .outOfReach
        default: .onPace
        }
    }

    /// Monday-first weekday index (Mon = 1 … Sun = 7) for a dayKey.
    static func weekdayIndex(of dayKey: String) -> Int {
        guard let date = DayKeyMath.date(from: dayKey) else { return 1 }
        // DayKeyMath parses dayKeys in the device timezone — read it back the same way.
        let weekday = Calendar.current.component(.weekday, from: date) // 1 = Sunday
        return (weekday + 5) % 7 + 1
    }

    /// Monday dayKey of the week containing the given dayKey.
    static func weekStart(of dayKey: String) -> String {
        DayKeyMath.addDays(dayKey, -(weekdayIndex(of: dayKey) - 1))
    }

    /// Elapsed full days of the week (0…7). Today only counts after 18:00
    /// (late-night hours before the 3 AM boundary count as "tonight").
    static func elapsedDays(dayKey: String, now: Date = .now) -> Int {
        let index = weekdayIndex(of: dayKey)
        let hour = Calendar.current.component(.hour, from: now)
        let todayCounts = hour >= 18 || DayKeyMath.isLateNight(now: now)
        return todayCounts ? index : max(index - 1, 0)
    }

    /// Where the pace tick sits: target × elapsed / 7.
    static func expectedByTonight(target: Int, dayKey: String, now: Date = .now) -> Double {
        Double(target) * Double(elapsedDays(dayKey: dayKey, now: now)) / 7
    }

    /// Client-side pace status for contexts without a server PaceDTO
    /// (Habit Detail). Same display rule as the server.
    static func weeklyStatus(total: Int, target: Int, dayKey: String, now: Date = .now) -> PaceDisplayStatus {
        if total >= target { return .weekDone }
        let remainingDays = 7 - weekdayIndex(of: dayKey) + 1 // including today
        if total + remainingDays < target { return .outOfReach }
        let needed = Int(ceil(expectedByTonight(target: target, dayKey: dayKey, now: now)))
        return total >= needed ? .onPace : .behind(needed - total)
    }

    /// Whether an entry counts as "on pace" for the Habits header strip:
    /// weekly habits on pace or done, daily/multi habits at full credit today.
    static func isOnPace(_ entry: HabitTodayEntryDTO) -> Bool {
        switch entry.habit.type {
        case .weeklyFrequency:
            entry.pace?.kind == "on_pace" || entry.pace?.kind == "week_done"
        case .daily, .multiDaily:
            entry.repsToday >= entry.habit.targetReps
        }
    }

    /// "Jul 9" style short label.
    static func shortLabel(for dayKey: String) -> String {
        guard let date = DayKeyMath.date(from: dayKey) else { return dayKey }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
