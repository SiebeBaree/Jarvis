import SwiftUI

// MARK: - Daily score ring
//
// One continuous arc starting at 12 o'clock, filled to total/100 over a
// bg.subtle track — 31 reads as an unbroken 31% sweep. (Replaced the earlier
// three weight-proportional arcs: a partial day rendered as disconnected
// green fragments. Per-component detail lives in the bars next to the ring
// and in the breakdown sheet.) A nil total renders a dashed empty track + "—".

public struct ScoreRing: View {
    private let size: CGFloat
    private let total: Double?
    private let caption: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        size: CGFloat,
        total: Double?,
        caption: String = "today"
    ) {
        self.size = size
        self.total = total
        self.caption = caption
    }

    private var lineWidth: CGFloat { max(6, size / 12) }

    private var fill: Double? {
        total.map { min(max($0 / 100, 0), 1) }
    }

    public var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(
                    Color.bgSubtle,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: fill == nil ? .butt : .round,
                        dash: fill == nil ? [2, 4] : []
                    )
                )

            // Fill
            if let fill {
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(
                        Color.success,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
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
        .animation(reduceMotion ? nil : .spring(duration: 0.6), value: fill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Score \(total.map { "\(Int($0.rounded()))" } ?? "not available"), \(caption)"))
    }
}

#Preview("ScoreRing") {
    VStack(spacing: Space.xxl) {
        // Typical day
        ScoreRing(size: 120, total: 74)
        // Low partial day — one unbroken sweep, no fragments
        ScoreRing(size: 120, total: 31)
        // Empty day
        ScoreRing(size: 160, total: nil)
    }
    .padding()
    .background(Color.bgCanvas)
}

#Preview("ScoreRing animated") {
    @Previewable @State var total: Double = 20
    VStack(spacing: Space.xl) {
        ScoreRing(size: 160, total: total)
        Button("Randomize") { total = .random(in: 0...100) }
            .buttonStyle(.jarvisSecondary)
    }
    .padding()
    .background(Color.bgCanvas)
}
