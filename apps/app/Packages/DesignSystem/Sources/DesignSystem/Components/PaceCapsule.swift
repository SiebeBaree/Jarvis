import SwiftUI

// MARK: - Weekly habit pace indicator
//
// n segments (the weekly target) filling left-to-right in the habit's colour.
//
// The indicator stays silent while the week is still winnable. It used to
// compare you against a straight line through the week, which made a habit you
// do once on Sunday "1 behind" from Tuesday morning, and a gym week that skips
// Tuesday "1 behind" on a Wednesday you had every intention of training. Both
// were arithmetic, not information.
//
// So there are only two things worth saying: the day the last rep has to land,
// and the day the week can no longer be saved. Everything else is a count.
//
// NEVER red. Missing a day is not a failure in this app: only the weekly total
// counts, and every rep still counts toward it after the week is out of reach.

public enum PaceDisplayStatus: Equatable, Sendable {
    /// The target is still reachable with a day to spare.
    case onTrack
    /// Every remaining day now has to count, today included.
    case lastChance(daysLeft: Int)
    /// More reps left than days left. Nothing to do but keep logging.
    case outOfReach(daysLeft: Int)
    case weekDone
}

public struct PaceCapsule: View {
    private let target: Int
    private let done: Int
    private let mustHaveByTonight: Double
    private let status: PaceDisplayStatus
    private let tint: Color

    /// - Parameter mustHaveByTonight: reps that have to be logged by the end
    ///   of today for a full week to still be reachable. Zero for most of the
    ///   week, which is why the tick is usually hidden.
    public init(
        target: Int,
        done: Int,
        mustHaveByTonight: Double,
        status: PaceDisplayStatus,
        tint: Color = .success
    ) {
        self.target = max(target, 1)
        self.done = min(max(done, 0), max(target, 1))
        self.mustHaveByTonight = min(max(mustHaveByTonight, 0), Double(max(target, 1)))
        self.status = status
        self.tint = tint
    }

    private let segmentHeight: CGFloat = 6
    private let segmentSpacing: CGFloat = 3

    private var isOutOfReach: Bool {
        if case .outOfReach = status { return true }
        return false
    }

    private func segmentColor(at index: Int) -> Color {
        if index < done { return tint }
        if isOutOfReach, Double(index) < mustHaveByTonight { return .warning.opacity(0.28) }
        return .bgSubtle
    }

    private var showsTick: Bool {
        status != .weekDone && mustHaveByTonight > 0 && mustHaveByTonight < Double(target)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            segments
            statusLine
        }
        .jarvisAnimation(Motion.gauge, value: done)
    }

    private var segments: some View {
        HStack(spacing: segmentSpacing) {
            ForEach(0..<target, id: \.self) { index in
                Capsule()
                    .fill(segmentColor(at: index))
                    .frame(height: segmentHeight)
            }
        }
        .overlay {
            if showsTick {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.textTertiary)
                        .frame(width: 2, height: segmentHeight + 5)
                        .position(
                            x: proxy.size.width * mustHaveByTonight / Double(target),
                            y: proxy.size.height / 2
                        )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(done) of \(target) this week"))
    }

    private static func daysLabel(_ days: Int) -> String {
        days == 1 ? "1 day left" : "\(days) days left"
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: Space.xs) {
            Text("\(done)/\(target)")
                .font(.microJ)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
            switch status {
            case .onTrack:
                // No verdict. There is nothing to report about a week that is
                // going to be fine either way.
                Text("this week").font(.microJ).foregroundStyle(Color.textTertiary)
            case .lastChance(let days):
                separator
                Text(Self.daysLabel(days)).font(.microJ).foregroundStyle(Color.warning)
            case .outOfReach(let days):
                separator
                Text(Self.daysLabel(days)).font(.microJ).foregroundStyle(Color.textTertiary)
            case .weekDone:
                separator
                Text("Week done").font(.microJ).foregroundStyle(tint)
            }
        }
    }

    private var separator: some View {
        Text("·").font(.microJ).foregroundStyle(Color.textTertiary)
    }
}

#Preview("PaceCapsule") {
    VStack(alignment: .leading, spacing: Space.xl) {
        PaceCapsule(target: 5, done: 1, mustHaveByTonight: 0, status: .onTrack, tint: ItemColor.green.color)
        PaceCapsule(target: 5, done: 3, mustHaveByTonight: 3, status: .lastChance(daysLeft: 2), tint: ItemColor.blue.color)
        PaceCapsule(target: 5, done: 5, mustHaveByTonight: 4, status: .weekDone, tint: ItemColor.violet.color)
        PaceCapsule(target: 5, done: 1, mustHaveByTonight: 3, status: .outOfReach(daysLeft: 2))
        PaceCapsule(target: 1, done: 0, mustHaveByTonight: 1, status: .lastChance(daysLeft: 1), tint: ItemColor.orange.color)
    }
    .padding()
    .frame(width: 240)
    .background(Color.bgCanvas)
}
