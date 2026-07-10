import DesignSystem
import Foundation
import JarvisAPI
import SwiftUI

/// Shared display logic for the Plan tab: score-band colors, block/week
/// date math and labels, and track-status pill mapping.
enum PlanDisplay {
    /// Universal score bands (§A8): gray <50, amber 50–69, green ≥70.
    static func bandColor(_ avg: Double?) -> Color {
        guard let avg else { return .bgSubtle }
        if avg < 50 { return .textTertiary }
        if avg < 70 { return .warning }
        return .success
    }

    /// The next Monday strictly after the given dayKey.
    static func nextMonday(after dayKey: DayKey = DayKeyMath.todayKey()) -> DayKey {
        let index = HabitDisplay.weekdayIndex(of: dayKey) // Mon = 1 … Sun = 7
        return DayKeyMath.addDays(dayKey, 8 - index)
    }

    /// Monday dayKey of week `weekNumber` (1-based) within a block.
    static func weekStart(block: BlockDTO, weekNumber: Int) -> DayKey {
        DayKeyMath.addDays(block.startDate, (weekNumber - 1) * 7)
    }

    static func weekEnd(block: BlockDTO, weekNumber: Int) -> DayKey {
        DayKeyMath.addDays(weekStart(block: block, weekNumber: weekNumber), 6)
    }

    /// "Jul 7–13" (same month) or "Jul 28 – Aug 3".
    static func rangeLabel(from: DayKey, to: DayKey) -> String {
        guard let fromDate = DayKeyMath.date(from: from),
              let toDate = DayKeyMath.date(from: to)
        else { return "\(from) – \(to)" }
        let calendar = Calendar.current
        let sameMonth = calendar.component(.month, from: fromDate) == calendar.component(.month, from: toDate)
            && calendar.component(.year, from: fromDate) == calendar.component(.year, from: toDate)
        let fromLabel = fromDate.formatted(.dateTime.month(.abbreviated).day())
        if sameMonth {
            return "\(fromLabel)–\(toDate.formatted(.dateTime.day()))"
        }
        return "\(fromLabel) – \(toDate.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// "Week 7 · Jul 7–13" style label.
    static func weekLabel(block: BlockDTO, weekNumber: Int) -> String {
        let range = rangeLabel(
            from: weekStart(block: block, weekNumber: weekNumber),
            to: weekEnd(block: block, weekNumber: weekNumber),
        )
        return "Week \(weekNumber) · \(range)"
    }

    /// Whole calendar days from today until a dayKey (0 when today/past).
    static func daysAway(_ dayKey: DayKey) -> Int {
        guard let target = DayKeyMath.date(from: dayKey),
              let today = DayKeyMath.date(from: DayKeyMath.todayKey())
        else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: today, to: target).day ?? 0
        return max(days, 0)
    }

    /// "Updated Jul 3" style label for an ISO-8601 instant.
    static func instantLabel(_ iso: String) -> String? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: iso)
        }()
        guard let date else { return nil }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func trackStatusLabel(_ status: String) -> String? {
        switch status {
        case "on_track": "On track"
        case "at_risk": "At risk"
        case "done": "Done"
        default: nil
        }
    }

    static func trackStatusColor(_ status: String) -> Color {
        switch status {
        case "on_track": .success
        case "at_risk": .warning
        default: .textTertiary
        }
    }
}

// MARK: - Track-status pill

/// "On track" (green) / "At risk" (amber) / "Done" (gray) capsule.
struct TrackStatusPill: View {
    let status: String

    var body: some View {
        if let label = PlanDisplay.trackStatusLabel(status) {
            Text(label)
                .font(.captionJ)
                .foregroundStyle(PlanDisplay.trackStatusColor(status))
                .padding(.horizontal, Space.sm)
                .padding(.vertical, 2)
                .background(PlanDisplay.trackStatusColor(status).opacity(0.12), in: Capsule())
        }
    }
}

// MARK: - Progress bar

/// Thin goal-progress capsule (accent fill on subtle track).
struct PlanProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.bgSubtle)
                Capsule()
                    .fill(Color.accentPrimary)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
    }
}
