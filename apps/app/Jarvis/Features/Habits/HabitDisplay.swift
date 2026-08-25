import DesignSystem
import Foundation
import JarvisAPI

/// Navigation route to a habit's detail screen (pushed from Today and Habits).
struct HabitDetailRoute: Hashable, Identifiable {
    let habitId: String
    var id: String { habitId }
}

/// Shared display logic for habits (pace mapping, captions, week math).
/// Mirrors the server's weekly rule: a habit is only in trouble once its
/// target stops being reachable in the days that are left.
enum HabitDisplay {
    static func icon(for habit: HabitDTO) -> String {
        let name = habit.icon?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "circle.dashed" : name
    }

    /// A habit's colour identity, used by its tile, its check control, its
    /// calendar and its charts. Habits created before the picker existed have
    /// no `colorHex`, so they get a stable colour derived from their id rather
    /// than all defaulting to indigo and looking like one undifferentiated list.
    static func color(for habit: HabitDTO) -> ItemColor {
        if let hex = habit.colorHex, !hex.isEmpty {
            return ItemColor.named(hex)
        }
        return ItemColor.fallback(for: habit.id)
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
        case "last_chance": .lastChance(daysLeft: max(pace?.daysLeft ?? 1, 1))
        case "out_of_reach": .outOfReach(daysLeft: max(pace?.daysLeft ?? 1, 1))
        default: .onTrack
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

    /// Days left in the week, today included.
    static func daysLeft(from dayKey: String) -> Int {
        max(0, 8 - weekdayIndex(of: dayKey))
    }

    /// Reps that have to be logged by the end of today for a full week to
    /// still be reachable. Zero for most of the week, which is exactly why
    /// the pace tick is usually hidden.
    static func mustHaveByTonight(target: Int, dayKey: String) -> Double {
        Double(max(0, target - (daysLeft(from: dayKey) - 1)))
    }

    /// Client-side pace status for contexts without a server PaceDTO
    /// (Habit Detail). Same rule as the server.
    static func weeklyStatus(total: Int, target: Int, dayKey: String) -> PaceDisplayStatus {
        let remaining = max(1, target) - total
        if remaining <= 0 { return .weekDone }
        let days = daysLeft(from: dayKey)
        if remaining > days { return .outOfReach(daysLeft: days) }
        if remaining == days { return .lastChance(daysLeft: days) }
        return .onTrack
    }

    /// Whether an entry counts as "on track" for the Habits header strip:
    /// weekly habits whose week is still winnable, daily and multi habits at
    /// full credit today.
    static func isOnTrack(_ entry: HabitTodayEntryDTO) -> Bool {
        switch entry.habit.type {
        case .weeklyFrequency:
            entry.pace?.kind != "out_of_reach"
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
