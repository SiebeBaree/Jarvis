import DesignSystem
import JarvisAPI
import SwiftUI

/// Reusable recurrence rule editor: frequency, interval, weekday chips for
/// weekly rules, day-of-month stepper for monthly rules, plus a live summary.
struct RecurrenceRuleEditor: View {
    @Binding var rule: RecurrenceRuleDTO
    var defaultWeekday: Int = 1
    var defaultMonthDay: Int = 1

    private static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        Picker("Frequency", selection: frequencyBinding) {
            Text("Daily").tag("daily")
            Text("Weekly").tag("weekly")
            Text("Monthly").tag("monthly")
        }
        .pickerStyle(.segmented)

        Stepper(value: intervalBinding, in: 1...30) {
            Text(intervalLabel)
                .font(.bodyJ)
        }

        if rule.freq == "weekly" {
            weekdayChips
        }

        if rule.freq == "monthly" {
            Stepper(value: monthDayBinding, in: 1...31) {
                Text("Day of month: \(rule.byMonthDay ?? defaultMonthDay)")
                    .font(.bodyJ)
            }
            Text("Clamped in shorter months")
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
        }

        Text(rule.summaryText)
            .font(.subheadJ)
            .foregroundStyle(Color.textSecondary)
    }

    // MARK: - Bindings

    private var frequencyBinding: Binding<String> {
        Binding(
            get: { rule.freq },
            set: { newFreq in
                rule.freq = newFreq
                switch newFreq {
                case "weekly":
                    if (rule.byWeekday ?? []).isEmpty { rule.byWeekday = [defaultWeekday] }
                    rule.byMonthDay = nil
                case "monthly":
                    rule.byWeekday = nil
                    if rule.byMonthDay == nil { rule.byMonthDay = defaultMonthDay }
                default:
                    rule.byWeekday = nil
                    rule.byMonthDay = nil
                }
            },
        )
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { max(1, rule.interval) },
            set: { rule.interval = $0 },
        )
    }

    private var monthDayBinding: Binding<Int> {
        Binding(
            get: { rule.byMonthDay ?? defaultMonthDay },
            set: { rule.byMonthDay = $0 },
        )
    }

    private var intervalLabel: String {
        let unit: String = switch rule.freq {
        case "weekly": rule.interval == 1 ? "week" : "weeks"
        case "monthly": rule.interval == 1 ? "month" : "months"
        default: rule.interval == 1 ? "day" : "days"
        }
        return "Every \(rule.interval) \(unit)"
    }

    // MARK: - Weekday chips

    private var weekdayChips: some View {
        HStack(spacing: Space.xs) {
            ForEach(1...7, id: \.self) { weekday in
                let isOn = (rule.byWeekday ?? []).contains(weekday)
                Button {
                    toggleWeekday(weekday)
                } label: {
                    Text(Self.weekdayNames[weekday - 1])
                        .font(.captionJ)
                        .foregroundStyle(isOn ? Color.accentPrimary : Color.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(
                            isOn ? Color.accentSubtle : Color.bgSubtle,
                            in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous),
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleWeekday(_ weekday: Int) {
        var selected = Set(rule.byWeekday ?? [])
        if selected.contains(weekday) {
            // Keep at least one weekday selected.
            guard selected.count > 1 else { return }
            selected.remove(weekday)
        } else {
            selected.insert(weekday)
        }
        rule.byWeekday = selected.sorted()
    }
}

// MARK: - Human-readable summary

extension RecurrenceRuleDTO {
    /// "Every day", "Every 2 weeks on Mon, Thu", "Every month on day 1", ...
    var summaryText: String {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        switch freq {
        case "weekly":
            let days = (byWeekday ?? [])
                .sorted()
                .compactMap { (1...7).contains($0) ? names[$0 - 1] : nil }
                .joined(separator: ", ")
            let base = interval == 1 ? "Every week" : "Every \(interval) weeks"
            return days.isEmpty ? base : "\(base) on \(days)"
        case "monthly":
            let base = interval == 1 ? "Every month" : "Every \(interval) months"
            if let day = byMonthDay { return "\(base) on day \(day)" }
            return base
        default:
            return interval == 1 ? "Every day" : "Every \(interval) days"
        }
    }
}
