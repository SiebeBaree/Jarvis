import Foundation

/// Display-only mirror of the server's dayKey math (3 AM boundary).
/// The server is the source of truth for every persisted dayKey — the app
/// only uses this for "today" labels, countdowns, and calendar headers.
enum DayKeyMath {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Current dayKey in the device's timezone with the given boundary hour.
    static func todayKey(boundaryHour: Int = 3, now: Date = .now) -> String {
        let shifted = now.addingTimeInterval(-Double(boundaryHour) * 3600)
        return dayFormatter.string(from: shifted)
    }

    /// True between midnight and the boundary — the "Late night" state.
    static func isLateNight(boundaryHour: Int = 3, now: Date = .now) -> Bool {
        let hour = Calendar.current.component(.hour, from: now)
        return hour < boundaryHour
    }

    static func date(from dayKey: String) -> Date? {
        dayFormatter.date(from: dayKey)
    }

    static func addDays(_ dayKey: String, _ days: Int) -> String {
        guard let date = date(from: dayKey),
              let shifted = Calendar.current.date(byAdding: .day, value: days, to: date)
        else { return dayKey }
        return dayFormatter.string(from: shifted)
    }

    /// Whole days from `from` to `to` (negative when `to` is earlier).
    static func diffDays(_ from: String, _ to: String) -> Int {
        guard let start = date(from: from), let end = date(from: to) else { return 0 }
        return Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// "Thursday, July 10" style label for a dayKey.
    static func longLabel(for dayKey: String) -> String {
        guard let date = date(from: dayKey) else { return dayKey }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// "Jul 10" — compact enough for chips and inline copy.
    static func shortLabel(for dayKey: String) -> String {
        guard let date = date(from: dayKey) else { return dayKey }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Today" / "Yesterday" / "Sunday" — how the day pager names its pages.
    static func relativeLabel(for dayKey: String, today: String) -> String {
        switch diffDays(dayKey, today) {
        case 0: "Today"
        case 1: "Yesterday"
        default: date(from: dayKey)?.formatted(.dateTime.weekday(.wide)) ?? dayKey
        }
    }
}
