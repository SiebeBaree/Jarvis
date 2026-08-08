import SwiftUI

// MARK: - Check circle
//
// The single most-tapped control in the app: one tap completes a task or a
// daily habit. Everything about it is tuned for that.
//
// - The hit target is 44 pt regardless of the drawn size, so the ring can
//   look delicate without being hard to hit.
// - Turning ON overshoots (fill springs out past 1, checkmark lands after it)
//   and fires a success haptic. Turning OFF is quiet and quick — undoing a
//   mistake should not be celebrated.
// - The ring inherits the item's colour when it has one, which is what ties a
//   row's icon, its ring and its calendar dots together.

public struct CheckCircle: View {
    private let isOn: Bool
    private let tint: Color
    private let size: CGFloat
    private let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init(
        isOn: Bool,
        tint: Color = .success,
        size: CGFloat = 26,
        action: @escaping () -> Void
    ) {
        self.isOn = isOn
        self.tint = tint
        self.size = size
        self.action = action
    }

    public var body: some View {
        // Read out of the environment here: the keyframe closure below is
        // Sendable and cannot touch MainActor-isolated properties.
        let animates = !reduceMotion
        return Button {
            Haptics.play(isOn ? .light : .success)
            withJarvisAnimation(Motion.pop) { action() }
        } label: {
            ZStack {
                // Empty state ring. Stays under the fill so the fill can grow
                // out of it rather than replacing it.
                Circle()
                    .strokeBorder(isOn ? .clear : Color.borderStrong, lineWidth: 1.5)

                Circle()
                    .fill(tint)
                    .scaleEffect(isOn ? 1 : 0.1)
                    .opacity(isOn ? 1 : 0)

                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(isOn ? 1 : 0.4)
                    .opacity(isOn ? 1 : 0)
            }
            .frame(width: size, height: size)
            .keyframeAnimator(
                initialValue: 1.0,
                trigger: isOn,
            ) { view, scale in
                view.scaleEffect(animates ? scale : 1)
            } keyframes: { _ in
                // Only the ON direction gets the flourish; the OFF direction
                // still runs this but the values are close enough to 1 to read
                // as nothing happening.
                KeyframeTrack {
                    SpringKeyframe(isOn ? 1.22 : 1.0, duration: 0.14, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.26, spring: .bouncy)
                }
            }
            // Bigger than it looks — a 26 pt circle is a 44 pt target.
            .frame(width: RowHeight.tapTarget, height: RowHeight.tapTarget)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(isOn ? "Completed" : "Not completed")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("CheckCircle") {
    struct Demo: View {
        @State private var a = false
        @State private var b = true
        var body: some View {
            VStack(spacing: Space.xl) {
                HStack(spacing: Space.lg) {
                    CheckCircle(isOn: a) { a.toggle() }
                    CheckCircle(isOn: b, tint: ItemColor.violet.color) { b.toggle() }
                    CheckCircle(isOn: true, tint: ItemColor.amber.color, size: 32) {}
                    CheckCircle(isOn: false, size: 32) {}
                }
                Text("Tap the first two").font(.subheadJ).foregroundStyle(Color.textSecondary)
            }
            .padding()
            .background(Color.bgCanvas)
        }
    }
    return Demo()
}
