import DesignSystem
import SwiftUI

/// The in-flight state after Continue (§B6): 3 shimmer lines + a rotating
/// verb on a 3 s cadence; after 6 s a reassurance caption. Errors swap in an
/// inline card with Retry (re-sends the same answers).
struct ThinkingView: View {
    let error: String?
    let retry: () -> Void

    @State private var startDate = Date.now

    private static let verbs = [
        "Thinking…",
        "Connecting the dots…",
        "Drafting the next question…",
    ]

    var body: some View {
        if let error {
            errorCard(error)
        } else {
            thinkingCard
        }
    }

    // MARK: - Thinking

    private var thinkingCard: some View {
        TimelineView(.periodic(from: startDate, by: 3)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let index = max(Int(elapsed / 3), 0) % Self.verbs.count
            VStack(alignment: .leading, spacing: Space.md) {
                Text(Self.verbs[index])
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .animation(.easeOut(duration: 0.25), value: index)
                ShimmerLines()
                if elapsed >= 6 {
                    Text("Still thinking — good answers take a moment.")
                        .font(.captionJ)
                        .foregroundStyle(Color.textTertiary)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .jarvisCard()
        .accessibilityLabel("Thinking about your answers")
    }

    // MARK: - Error

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("That didn't go through")
                .font(.headlineJ)
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retry)
                .buttonStyle(.jarvisSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }
}

// MARK: - Shimmer lines (opacity-pulsed gradient; respects Reduce Motion)

private struct ShimmerLines: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            line(trailingInset: 0)
            line(trailingInset: 48)
            line(trailingInset: 112)
        }
        .opacity(dimmed ? 0.45 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        }
        .accessibilityHidden(true)
    }

    private func line(trailingInset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.bgSubtle, Color.bgHover, Color.bgSubtle],
                    startPoint: .leading,
                    endPoint: .trailing,
                )
            )
            .frame(height: 13)
            .padding(.trailing, trailingInset)
    }
}
