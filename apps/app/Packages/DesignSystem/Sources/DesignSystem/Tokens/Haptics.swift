import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Haptics
//
// Checking a habit off should be felt, not just seen. This is a large part of
// why a dedicated tracker feels better than a web app doing the same job, and
// it costs one line per call site.
//
// Silent no-op on Mac for the impact styles (there is no Taptic Engine on a
// non-trackpad Mac and NSHapticFeedbackManager only speaks in alignment
// feedback), so call sites never need a platform check.

public enum Haptics {
    public enum Style: Sendable {
        /// Selection changed, row pressed.
        case light
        /// A thing was logged or created.
        case medium
        /// Completion — a habit hit its target, a task closed.
        case success
        /// A destructive or rejected action.
        case warning
    }

    @MainActor
    public static func play(_ style: Style) {
        #if os(iOS)
        switch style {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #elseif os(macOS)
        // The only feedback a Mac trackpad exposes; still worth firing for
        // the completion moments.
        switch style {
        case .success, .medium:
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        case .warning:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        case .light:
            break
        }
        #endif
    }

    /// Warms the generator so the *first* tap is not the one that stutters.
    /// Called once when a screen full of tappable rows appears.
    @MainActor
    public static func prepare() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).prepare()
        UINotificationFeedbackGenerator().prepare()
        #endif
    }
}
