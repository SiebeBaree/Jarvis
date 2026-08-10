import DesignSystem
import SwiftUI

/// Ambient sync state. Writes land in the background, so the only thing worth
/// interrupting for is a write that has NOT landed — being offline with a
/// clean queue is not a problem worth a banner, and a queue that is draining
/// normally resolves in well under a second.
struct SyncStatusBar: View {
    @Environment(AppModel.self) private var model

    /// Pending work is only surfaced once it has visibly stalled; a normal
    /// flush would otherwise flash a banner on every tap.
    @State private var stalled = false

    private var pendingCount: Int { model.queue.pending.count }

    var body: some View {
        Group {
            if let failure = model.queue.failure {
                bar(
                    icon: "exclamationmark.triangle",
                    tint: .danger,
                    text: failure,
                    action: ("Dismiss", { model.queue.failure = nil }),
                )
            } else if stalled, pendingCount > 0 {
                bar(
                    icon: model.queue.isOffline ? "wifi.slash" : "arrow.triangle.2.circlepath",
                    tint: .textSecondary,
                    text: model.queue.isOffline
                        ? "Offline. \(pendingCount) change\(pendingCount == 1 ? "" : "s") will sync when you reconnect"
                        : "Syncing \(pendingCount) change\(pendingCount == 1 ? "" : "s")…",
                    action: nil,
                )
            }
        }
        .jarvisAnimation(Motion.smooth, value: stalled)
        .jarvisAnimation(Motion.smooth, value: model.queue.failure)
        .task(id: pendingCount) {
            guard pendingCount > 0 else {
                stalled = false
                return
            }
            try? await Task.sleep(for: .seconds(2))
            stalled = !Task.isCancelled
        }
    }

    private func bar(
        icon: String,
        tint: Color,
        text: String,
        action: (label: String, run: () -> Void)?,
    ) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.microJ)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
            if let action {
                Spacer(minLength: Space.sm)
                Button(action.label, action: action.run)
                    .buttonStyle(.jarvisSoft)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(.regularMaterial, in: Capsule())
        .jarvisShadow(.floating)
        .padding(.horizontal, PageMargin.standard)
        // Clears the floating tab bar on iOS; on Mac it sits at the window edge.
        #if os(iOS)
        .padding(.bottom, 96)
        #else
        .padding(.bottom, Space.md)
        #endif
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
