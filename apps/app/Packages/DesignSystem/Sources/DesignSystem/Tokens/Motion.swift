import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Motion tokens
//
// One vocabulary of curves, used everywhere. The old code sprinkled
// `.easeOut(duration: 0.15/0.2/0.25)` per call site, which is why nothing
// felt like it belonged to the same app: every screen had its own timing.
//
// All of these are springs. A linear ease reads as "a value changed"; a
// spring reads as "an object moved", and that difference is most of what
// separates a native-feeling app from a web page in a wrapper.

public enum Motion {
    /// The default. Anything that moves, appears, or reflows.
    public static let standard = Animation.spring(response: 0.34, dampingFraction: 0.85)

    /// Snappier — chips, selection, small state flips that should feel instant.
    public static let quick = Animation.spring(response: 0.24, dampingFraction: 0.88)

    /// Overshoots. Reserved for completion moments: a check landing, a rep
    /// registering. This is the app's reward animation, so it is deliberately
    /// the only bouncy curve.
    public static let pop = Animation.spring(response: 0.3, dampingFraction: 0.58)

    /// Slow and heavily damped — the score ring, progress bars, anything
    /// where the *travel* is the information.
    public static let gauge = Animation.spring(response: 0.75, dampingFraction: 0.9)

    /// Layout changes that move a lot of pixels: sheets, expanding sections.
    public static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.92)
}

// MARK: - Reduce Motion

public extension View {
    /// Applies `animation` unless the user asked for reduced motion, in which
    /// case the value still changes — instantly. Every animated property in
    /// the app goes through this, so honouring the setting is not something
    /// an individual view has to remember.
    func jarvisAnimation<V: Equatable>(_ animation: Animation = Motion.standard, value: V) -> some View {
        modifier(ReduceMotionAnimation(animation: animation, value: value))
    }
}

private struct ReduceMotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// `withAnimation` that respects Reduce Motion. Reads the setting from the
/// platform rather than the environment, so it works from stores and
/// callbacks that have no `View` context.
@MainActor
public func withJarvisAnimation<Result>(
    _ animation: Animation = Motion.standard,
    _ body: () throws -> Result
) rethrows -> Result {
    if ReduceMotion.isEnabled {
        return try body()
    }
    return try withAnimation(animation, body)
}

public enum ReduceMotion {
    @MainActor
    public static var isEnabled: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #elseif canImport(AppKit)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        false
        #endif
    }
}

// MARK: - Press feedback
//
// A row that does nothing under the finger feels dead. This scales and dims
// on touch-down, which is the cheapest possible "this is a real control"
// signal — and it is applied to every tappable row in the app.

public struct PressableModifier: ViewModifier {
    @State private var isPressed = false
    private let scale: CGFloat
    private let haptic: Haptics.Style?
    private let action: () -> Void

    public init(scale: CGFloat = 0.97, haptic: Haptics.Style? = .light, action: @escaping () -> Void) {
        self.scale = scale
        self.haptic = haptic
        self.action = action
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1)
            .opacity(isPressed ? 0.85 : 1)
            .jarvisAnimation(Motion.quick, value: isPressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                    }
                    .onEnded { value in
                        isPressed = false
                        // Treat it as a tap only if the finger stayed put —
                        // otherwise a scroll that began on this row would fire it.
                        let travel = abs(value.translation.width) + abs(value.translation.height)
                        guard travel < 12 else { return }
                        if let haptic { Haptics.play(haptic) }
                        action()
                    }
            )
    }
}

public extension View {
    /// Tap handler with press feedback and a haptic. Use instead of
    /// `.onTapGesture` for anything that looks like a control.
    func pressable(
        scale: CGFloat = 0.97,
        haptic: Haptics.Style? = .light,
        action: @escaping () -> Void
    ) -> some View {
        modifier(PressableModifier(scale: scale, haptic: haptic, action: action))
    }
}
