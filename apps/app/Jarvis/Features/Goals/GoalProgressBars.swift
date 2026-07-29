import DesignSystem
import JarvisAPI
import SwiftUI

/// The two-bar block every goal card and detail screen is built around:
/// progress on top, time below it. Stacked and identically scaled so the gap
/// between them reads at a glance — that gap is the whole signal.
struct GoalProgressBars: View {
    let goal: GoalDTO
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : Space.xs) {
            if let progress = goal.progress {
                bar(
                    label: "Progress",
                    fraction: progress,
                    color: paceColor,
                    trailing: percentLabel(progress),
                )
            }
            bar(
                label: "Time",
                fraction: goal.timeProgress,
                color: .textTertiary,
                trailing: timeLabel,
            )
        }
    }

    /// Green when the work is at least keeping up with the clock, amber when
    /// it has slipped behind by more than a rounding error, red once the date
    /// has passed with the goal unfinished.
    private var paceColor: Color {
        guard let progress = goal.progress else { return .accentPrimary }
        if progress >= 1 { return .success }
        if goal.daysRemaining < 0 { return .danger }
        return progress + 0.05 >= goal.timeProgress ? .success : .warning
    }

    private var timeLabel: String {
        let remaining = goal.daysRemaining
        if remaining < 0 { return "\(-remaining)d over" }
        if remaining == 0 { return "due today" }
        if remaining < 14 { return "\(remaining)d left" }
        if remaining < 70 { return "\(remaining / 7)w left" }
        return "\(remaining / 30)mo left"
    }

    private func percentLabel(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private func bar(label: String, fraction: Double, color: Color, trailing: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Space.sm) {
                Text(label)
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
                Spacer(minLength: Space.xs)
                Text(trailing)
                    .font(.monoJ)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bgSubtle)
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(percentLabel(fraction)), \(trailing)")
    }
}

/// "3,400 / 10,000 EUR" — the numeric goal's headline figure.
enum GoalValueFormat {
    static let number: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func string(_ value: Double) -> String {
        number.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func summary(_ goal: GoalDTO) -> String? {
        guard let target = goal.targetValue else { return nil }
        let current = goal.currentValue ?? goal.startValue ?? 0
        let unit = goal.unit.map { " \($0)" } ?? ""
        return "\(string(current)) / \(string(target))\(unit)"
    }
}
