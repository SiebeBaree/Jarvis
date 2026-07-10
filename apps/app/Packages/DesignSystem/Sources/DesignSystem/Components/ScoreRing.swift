import SwiftUI

// MARK: - Daily score ring (spec §B5.1)
//
// One ring, three arcs sized proportionally to their weights
// (e.g. 40/40/20 → 144°/144°/72°) with 4° gaps between arcs.
// Each arc has a bg.subtle track and fills by its component completion.
// Tasks = accent indigo · Habits = success green · Feel = warning→success tint.
// A nil fill renders that arc's track dashed and empty (mood unset).

public struct ScoreRing: View {
    private let size: CGFloat
    private let weights: (tasks: Double, habits: Double, feel: Double)
    private let taskFill: Double?
    private let habitFill: Double?
    private let feelFill: Double?
    private let total: Double?
    private let caption: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        size: CGFloat,
        weights: (tasks: Double, habits: Double, feel: Double) = (40, 40, 20),
        taskFill: Double?,
        habitFill: Double?,
        feelFill: Double?,
        total: Double?,
        caption: String = "today"
    ) {
        self.size = size
        self.weights = weights
        self.taskFill = taskFill
        self.habitFill = habitFill
        self.feelFill = feelFill
        self.total = total
        self.caption = caption
    }

    private var lineWidth: CGFloat { max(6, size / 12) }

    private struct Arc: Identifiable {
        let id: Int
        /// Track start/end as fractions of the full circle, starting at 12 o'clock.
        let start: Double
        let end: Double
        /// Component completion in [0, 1]; nil = unset (dashed empty track).
        let fill: Double?
        let color: Color
    }

    private var arcs: [Arc] {
        let weightSum = max(weights.tasks + weights.habits + weights.feel, .ulpOfOne)
        let gap = 4.0 / 360.0

        let feelValue = feelFill.map { min(max($0, 0), 1) }
        let feelColor = Color.warning.mix(with: .success, by: feelValue ?? 0)

        let specs: [(weight: Double, fill: Double?, color: Color)] = [
            (weights.tasks, taskFill, .accentPrimary),
            (weights.habits, habitFill, .success),
            (weights.feel, feelValue, feelColor),
        ]

        var cursor = 0.0
        var result: [Arc] = []
        for (index, spec) in specs.enumerated() {
            let span = spec.weight / weightSum
            let start = cursor + gap / 2
            let end = cursor + span - gap / 2
            result.append(Arc(
                id: index,
                start: start,
                end: max(start, end),
                fill: spec.fill.map { min(max($0, 0), 1) },
                color: spec.color
            ))
            cursor += span
        }
        return result
    }

    /// Equatable animation trigger for the three fills.
    private var animationValue: [Double] {
        [taskFill ?? -1, habitFill ?? -1, feelFill ?? -1]
    }

    public var body: some View {
        ZStack {
            ForEach(arcs) { arc in
                // Track
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(
                        Color.bgSubtle,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: arc.fill == nil ? .butt : .round,
                            dash: arc.fill == nil ? [2, 4] : []
                        )
                    )
                    .rotationEffect(.degrees(-90))

                // Fill
                if let fill = arc.fill {
                    Circle()
                        .trim(from: arc.start, to: arc.start + fill * (arc.end - arc.start))
                        .stroke(
                            arc.color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }

            VStack(spacing: 0) {
                Text(total.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.displayScore)
                    .foregroundStyle(Color.textPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(caption)
                    .font(.captionJ)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(lineWidth * 2)
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .spring(duration: 0.6), value: animationValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Score \(total.map { "\(Int($0.rounded()))" } ?? "not available"), \(caption)"))
    }
}

#Preview("ScoreRing") {
    VStack(spacing: Space.xxl) {
        // Typical day
        ScoreRing(size: 120, taskFill: 0.7, habitFill: 0.8, feelFill: 0.72, total: 74)
        // Mood unset → feel arc dashed, score renormalized
        ScoreRing(size: 120, taskFill: 0.5, habitFill: 0.25, feelFill: nil, total: 38)
        // Empty day
        ScoreRing(size: 160, taskFill: 0, habitFill: 0, feelFill: nil, total: nil)
    }
    .padding()
    .background(Color.bgCanvas)
}

#Preview("ScoreRing animated") {
    @Previewable @State var fill: Double = 0.2
    VStack(spacing: Space.xl) {
        ScoreRing(size: 160, taskFill: fill, habitFill: 1 - fill, feelFill: fill, total: fill * 100)
        Button("Randomize") { fill = .random(in: 0...1) }
            .buttonStyle(.jarvisSecondary)
    }
    .padding()
    .background(Color.bgCanvas)
}
