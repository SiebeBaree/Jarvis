import Foundation
import JarvisAPI

/// What the quick-add field understood from the typed text: the title with
/// every recognized phrase removed, plus the fields those phrases set. A nil
/// field means "not mentioned" — the composer keeps whatever the chips say.
struct QuickAddParse: Equatable {
    var title: String = ""
    var dueDate: DayKey?
    var dueTime: String?
    var priority: TaskPriority?
    var categoryId: String?
}

/// TickTick-style natural language for the quick-add field, so
/// "gym tomorrow 7pm !1 #health" is one run of typing instead of four taps.
///
/// Deliberately conservative: only phrases it is sure about are consumed, and
/// anything it does not recognize stays in the title verbatim. Numeric dates
/// ("5/8") are *not* parsed — day-first and month-first readings are both
/// plausible, and guessing wrong is worse than making you tap the calendar.
enum QuickAddParser {
    static func parse(
        _ text: String,
        today: DayKey,
        categories: [TaskCategoryDTO] = [],
    ) -> QuickAddParse {
        var parse = QuickAddParse()
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var kept: [String] = []
        var index = 0
        while index < tokens.count {
            let eaten = consume(tokens, at: index, today: today, categories: categories, into: &parse)
            if eaten > 0 {
                index += eaten
            } else {
                kept.append(tokens[index])
                index += 1
            }
        }
        parse.title = kept.joined(separator: " ")
        return parse
    }

    /// Tries every pattern at `index`; returns how many tokens it swallowed.
    private static func consume(
        _ tokens: [String],
        at index: Int,
        today: DayKey,
        categories: [TaskCategoryDTO],
        into parse: inout QuickAddParse,
    ) -> Int {
        let word = clean(tokens[index])
        guard !word.isEmpty else { return 0 }
        let next = index + 1 < tokens.count ? clean(tokens[index + 1]) : ""
        let third = index + 2 < tokens.count ? clean(tokens[index + 2]) : ""

        // #category — longest match first, so "#deep work" beats "#deep".
        if word.hasPrefix("#"), parse.categoryId == nil {
            let words = [word, next, third].filter { !$0.isEmpty }
            for length in stride(from: words.count, through: 1, by: -1) {
                let name = String(words.prefix(length).joined(separator: " ").dropFirst())
                guard !name.isEmpty, let match = category(named: name, in: categories) else { continue }
                parse.categoryId = match.id
                return length
            }
        }

        // !1 / !2 / !3 priority flags.
        if parse.priority == nil, let priority = priority(from: word) {
            parse.priority = priority
            return 1
        }

        // "at 5pm" / "at 17:00" — the "at" is part of the phrase.
        if word == "at", parse.dueTime == nil, let time = time(from: next) {
            parse.dueTime = time
            return 2
        }

        if parse.dueTime == nil, let time = time(from: word) {
            parse.dueTime = time
            return 1
        }

        guard parse.dueDate == nil else { return 0 }

        // "in 3 days" / "in 2 weeks" / "in 1 month".
        if word == "in", let amount = Int(next), amount > 0, let unit = unit(from: third) {
            parse.dueDate = shift(today, by: amount, unit: unit)
            return 3
        }

        // "next week" / "next month" / "next friday".
        if word == "next" {
            if next == "week" {
                parse.dueDate = DayKeyMath.addDays(today, 7)
                return 2
            }
            if next == "month" {
                parse.dueDate = shift(today, by: 1, unit: .month)
                return 2
            }
            if next == "weekend" {
                parse.dueDate = weekend(from: today)
                return 2
            }
            if let weekday = weekday(from: next) {
                parse.dueDate = nextWeekday(weekday, from: today)
                return 2
            }
        }

        // "this weekend" / "this friday".
        if word == "this" {
            if next == "weekend" {
                parse.dueDate = weekend(from: today)
                return 2
            }
            if let weekday = weekday(from: next) {
                parse.dueDate = nextWeekday(weekday, from: today)
                return 2
            }
        }

        // "aug 5" / "august 5th" / "5 aug".
        if let month = month(from: word), let day = dayNumber(from: next) {
            parse.dueDate = calendarDate(month: month, day: day, from: today)
            return 2
        }
        if let day = dayNumber(from: word), let month = month(from: next) {
            parse.dueDate = calendarDate(month: month, day: day, from: today)
            return 2
        }

        switch word {
        case "today":
            parse.dueDate = today
            return 1
        case "tonight":
            parse.dueDate = today
            if parse.dueTime == nil { parse.dueTime = "20:00" }
            return 1
        case "tomorrow", "tmr", "tmrw":
            parse.dueDate = DayKeyMath.addDays(today, 1)
            return 1
        case "weekend":
            parse.dueDate = weekend(from: today)
            return 1
        default:
            break
        }

        if let weekday = weekday(from: word) {
            parse.dueDate = nextWeekday(weekday, from: today)
            return 1
        }

        return 0
    }

    // MARK: - Token helpers

    /// Lowercased and stripped of the punctuation that trails a word in a
    /// sentence — but never of "!", which is the priority marker.
    private static func clean(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;:()\"'"))
    }

    private static func priority(from word: String) -> TaskPriority? {
        switch word {
        case "!1", "!high", "!p1": .high
        case "!2", "!medium", "!p2": .medium
        case "!3", "!low", "!p3": .low
        default: nil
        }
    }

    private static func category(named name: String, in categories: [TaskCategoryDTO]) -> TaskCategoryDTO? {
        let target = name.lowercased()
        let squashed = target.replacingOccurrences(of: " ", with: "")
        return categories.first {
            let candidate = $0.name.lowercased()
            return candidate == target || candidate.replacingOccurrences(of: " ", with: "") == squashed
        }
    }

    /// "5pm", "5:30pm", "9am", "17:00", "noon", "midnight" → "HH:mm".
    /// Bare numbers are never times: "buy 2 eggs" must stay a title.
    private static func time(from word: String) -> String? {
        if word == "noon" { return "12:00" }
        if word == "midnight" { return "00:00" }

        var body = word
        var meridiem: String?
        if body.hasSuffix("am") || body.hasSuffix("pm") {
            meridiem = String(body.suffix(2))
            body = String(body.dropLast(2))
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard let hourPart = parts.first, var hour = Int(hourPart), parts.count <= 2 else { return nil }
        var minute = 0
        if parts.count == 2 {
            guard let parsed = Int(parts[1]), parts[1].count == 2, (0..<60).contains(parsed) else { return nil }
            minute = parsed
        } else if meridiem == nil {
            // No colon and no am/pm — just a number, not a time.
            return nil
        }
        switch meridiem {
        case "am":
            guard (1...12).contains(hour) else { return nil }
            if hour == 12 { hour = 0 }
        case "pm":
            guard (1...12).contains(hour) else { return nil }
            if hour < 12 { hour += 12 }
        default:
            guard (0...23).contains(hour) else { return nil }
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    private enum Unit {
        case day, week, month
    }

    private static func unit(from word: String) -> Unit? {
        switch word {
        case "day", "days": .day
        case "week", "weeks": .week
        case "month", "months": .month
        default: nil
        }
    }

    private static func shift(_ dayKey: DayKey, by amount: Int, unit: Unit) -> DayKey {
        switch unit {
        case .day: DayKeyMath.addDays(dayKey, amount)
        case .week: DayKeyMath.addDays(dayKey, amount * 7)
        case .month: addMonths(dayKey, amount)
        }
    }

    private static func addMonths(_ dayKey: DayKey, _ months: Int) -> DayKey {
        guard let date = DayKeyMath.date(from: dayKey),
              let shifted = Calendar.current.date(byAdding: .month, value: months, to: date)
        else { return dayKey }
        return DayKeyMath.dayFormatter.string(from: shifted)
    }

    /// ISO weekday, 1 = Monday … 7 = Sunday.
    private static func weekday(from word: String) -> Int? {
        switch word {
        case "monday", "mon": 1
        case "tuesday", "tue", "tues": 2
        case "wednesday", "wed": 3
        case "thursday", "thu", "thur", "thurs": 4
        case "friday", "fri": 5
        case "saturday", "sat": 6
        case "sunday", "sun": 7
        default: nil
        }
    }

    /// The next time that weekday comes around — always in the future, so
    /// "monday" typed on a Monday means the one a week out, not right now.
    private static func nextWeekday(_ target: Int, from today: DayKey) -> DayKey {
        guard let date = DayKeyMath.date(from: today) else { return today }
        let current = isoWeekday(of: date)
        var delta = target - current
        if delta <= 0 { delta += 7 }
        return DayKeyMath.addDays(today, delta)
    }

    /// Saturday — or today, when the weekend has already started.
    private static func weekend(from today: DayKey) -> DayKey {
        guard let date = DayKeyMath.date(from: today) else { return today }
        let current = isoWeekday(of: date)
        if current >= 6 { return today }
        return DayKeyMath.addDays(today, 6 - current)
    }

    private static func isoWeekday(of date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date) // 1 = Sunday
        return weekday == 1 ? 7 : weekday - 1
    }

    private static func month(from word: String) -> Int? {
        let names = [
            ["january", "jan"], ["february", "feb"], ["march", "mar"], ["april", "apr"],
            ["may"], ["june", "jun"], ["july", "jul"], ["august", "aug"],
            ["september", "sep", "sept"], ["october", "oct"], ["november", "nov"], ["december", "dec"],
        ]
        guard let index = names.firstIndex(where: { $0.contains(word) }) else { return nil }
        return index + 1
    }

    /// "5", "5th", "22nd" → the day number.
    private static func dayNumber(from word: String) -> Int? {
        var body = word
        for suffix in ["st", "nd", "rd", "th"] where body.hasSuffix(suffix) {
            body = String(body.dropLast(2))
            break
        }
        guard let day = Int(body), (1...31).contains(day) else { return nil }
        return day
    }

    /// A month/day pair in the nearest future year — "jan 3" typed in
    /// December means next January, not eleven months ago.
    private static func calendarDate(month: Int, day: Int, from today: DayKey) -> DayKey {
        guard let todayDate = DayKeyMath.date(from: today) else { return today }
        var components = Calendar.current.dateComponents([.year], from: todayDate)
        components.month = month
        components.day = day
        guard let date = Calendar.current.date(from: components) else { return today }
        let key = DayKeyMath.dayFormatter.string(from: date)
        if key >= today { return key }
        components.year = (components.year ?? 0) + 1
        guard let nextYear = Calendar.current.date(from: components) else { return key }
        return DayKeyMath.dayFormatter.string(from: nextYear)
    }
}
