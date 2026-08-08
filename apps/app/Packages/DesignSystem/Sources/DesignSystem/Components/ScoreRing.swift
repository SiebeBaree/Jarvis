import SwiftUI

// MARK: - Daily score ring
//
// One continuous arc from 12 o'clock, filled to total/100, drawn in the
// violet→blue score gradient. The number inside rolls rather than cutting,
// so completing a task visibly *moves* the score — which is the only reward
// loop the app has.
//
// A nil total (nothing scoreable that day) renders a dashed track and "—",
// never a zero: an empty day is not a failed day.

public struct ScoreRing: View {
    private let size: CGFloat
    private let total: Double?
    private let caption: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: CGFloat, total: Double?, caption: String? = "today") {
        self.size = size
        self.total = total
        self.caption = caption
    }

    private var lineWidth: CGFloat { max(8, size / 10) }

    private var fill: Double? {
        total.map { min(max($0 / 100, 0), 1) }
    }

    private var value: Int? {
        total.map { Int($0.rounded()) }
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.bgSubtle,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: fill == nil ? .butt : .round,
                        dash: fill == nil ? [2, 5] : []
                    )
                )

            if let fill {
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(
                        AngularGradient.scoreArc,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: -2) {
                HStack(alignment: .top, spacing: 1) {
                    Text(value.map(String.init) ?? "—")
                        .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(value ?? 0)))
                    if value != nil {
                        Text("%")
                            .font(.system(size: size * 0.15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.textTertiary)
                            .padding(.top, size * 0.06)
                    }
                }
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

                if let caption {
                    Text(caption)
                        .font(.system(size: size * 0.095, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(lineWidth * 1.6)
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .jarvisAnimation(Motion.gauge, value: fill)
        .jarvisAnimation(Motion.gauge, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("Score \(value.map(String.init) ?? "not available")\(caption.map { ", \($0)" } ?? "")")
        )
    }
}

// MARK: - Component bar
//
// The "why" under the ring: one row per score component, with the bar doing
// the comparing so you never have to read two fractions and subtract.

public struct ComponentBar: View {
    private let label: String
    private let points: Double?
    private let weight: Double
    private let tint: Color

    public init(label: String, points: Double?, weight: Double, tint: Color) {
        self.label = label
        self.points = points
        self.weight = weight
        self.tint = tint
    }

    private var fill: Double {
        guard let points, weight > 0 else { return 0 }
        return min(max(points / weight, 0), 1)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Space.sm) {
                Text(label)
                    .font(.subheadStrongJ)
                    .foregroundStyle(Color.textSecondary)
                Spacer(minLength: Space.sm)
                Text(points.map { "\(Self.format($0))/\(Self.format(weight))" } ?? "—")
                    .font(.monoJ)
                    .foregroundStyle(points == nil ? Color.textTertiary : Color.textPrimary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bgSubtle)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(proxy.size.width * fill, fill > 0 ? 6 : 0))
                }
            }
            .frame(height: 6)
        }
        .jarvisAnimation(Motion.gauge, value: fill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(label), \(points.map { "\(Self.format($0)) of \(Self.format(weight)) points" } ?? "not applicable")")
        )
    }

    public static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }
}

#Preview("ScoreRing") {
    struct Demo: View {
        @State private var total: Double = 62
        var body: some View {
            VStack(spacing: Space.xxl) {
                ScoreRing(size: 132, total: total)
                VStack(spacing: Space.md) {
                    ComponentBar(label: "Tasks", points: total * 0.4, weight: 40, tint: .accentPrimary)
                    ComponentBar(label: "Habits", points: total * 0.4, weight: 40, tint: .success)
                    ComponentBar(label: "Feel", points: nil, weight: 20, tint: .warning)
                }
                .frame(width: 240)
                Button("Randomize") { total = .random(in: 0...100) }
                    .buttonStyle(.jarvisSecondary)
                ScoreRing(size: 96, total: nil, caption: "no data")
            }
            .padding()
            .background(Color.bgCanvas)
        }
    }
    return Demo()
}
