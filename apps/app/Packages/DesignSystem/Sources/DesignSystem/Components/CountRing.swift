import SwiftUI

// MARK: - Count ring
//
// The control for habits that are counted rather than checked: "8 glasses of
// water", "3 gym sessions this week". One tap logs one rep, the arc grows,
// the number rolls over, and when the target is met the whole thing flips to
// a filled check.
//
// It replaces the old pips-plus-"+1"-capsule pair, which needed two controls
// and ~120 pt of row width to say what this says in 34 pt.

public struct CountRing: View {
    private let done: Int
    private let target: Int
    private let tint: Color
    private let size: CGFloat
    private let action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init(
        done: Int,
        target: Int,
        tint: Color = .accentPrimary,
        size: CGFloat = 34,
        action: (() -> Void)? = nil
    ) {
        self.done = max(done, 0)
        self.target = max(target, 1)
        self.tint = tint
        self.size = size
        self.action = action
    }

    private var isComplete: Bool { done >= target }

    /// Wraps past 1 for overshoot (5 of 3 sessions) so the ring stays full
    /// rather than drawing a second lap.
    private var fill: Double { min(Double(done) / Double(target), 1) }

    private var lineWidth: CGFloat { max(3, size * 0.1) }

    public var body: some View {
        // Read out of the environment here: the keyframe closure below is
        // Sendable and cannot touch MainActor-isolated properties.
        let animates = !reduceMotion
        let content = ZStack {
            Circle()
                .stroke(Color.bgSubtle, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: fill)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Completed state: the ring fills in and the number gives way to
            // a check, so a finished habit is legible at a glance from across
            // a list.
            Circle()
                .fill(tint)
                .scaleEffect(isComplete ? 1 : 0.1)
                .opacity(isComplete ? 1 : 0)

            Image(systemName: "checkmark")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .opacity(isComplete ? 1 : 0)
                .scaleEffect(isComplete ? 1 : 0.4)

            Text("\(done)")
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText(value: Double(done)))
                .opacity(isComplete ? 0 : 1)
        }
        .frame(width: size, height: size)
        .jarvisAnimation(Motion.gauge, value: fill)
        .jarvisAnimation(Motion.pop, value: isComplete)
        .keyframeAnimator(initialValue: 1.0, trigger: done) { view, scale in
            view.scaleEffect(animates ? scale : 1)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(1.16, duration: 0.13, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.25, spring: .bouncy)
            }
        }

        if let action {
            Button {
                Haptics.play(done + 1 >= target ? .success : .medium)
                withJarvisAnimation(Motion.pop) { action() }
            } label: {
                content
                    .frame(width: max(size, RowHeight.tapTarget), height: max(size, RowHeight.tapTarget))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.4)
            .accessibilityLabel("\(done) of \(target)")
            .accessibilityHint("Logs one more")
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(done) of \(target)")
        }
    }
}

#Preview("CountRing") {
    struct Demo: View {
        @State private var water = 3
        @State private var gym = 2
        var body: some View {
            VStack(spacing: Space.xl) {
                HStack(spacing: Space.xl) {
                    CountRing(done: water, target: 8, tint: ItemColor.blue.color) { water += 1 }
                    CountRing(done: gym, target: 3, tint: ItemColor.green.color) { gym += 1 }
                    CountRing(done: 12, target: 10, tint: ItemColor.orange.color)
                    CountRing(done: 0, target: 5, tint: ItemColor.violet.color, size: 44)
                }
                Button("Reset") { water = 0; gym = 0 }
                    .buttonStyle(.jarvisSecondary)
            }
            .padding()
            .background(Color.bgCanvas)
        }
    }
    return Demo()
}
