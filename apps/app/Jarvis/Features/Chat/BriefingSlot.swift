import DesignSystem
import JarvisAPI
import SwiftUI

/// Morning briefing card on Today (§B3): expanded on the first open of the
/// day, a collapsed one-liner afterwards. Fetched lazily once per dayKey.
struct BriefingSlot: View {
    @Environment(AppModel.self) private var model

    let payload: DayPayload

    /// Last dayKey whose briefing the user has already seen expanded —
    /// subsequent opens that day start collapsed.
    @AppStorage("briefingSeenDayKey") private var seenDayKey = ""

    @State private var state: LoadState<BriefingDTO> = .idle
    @State private var expanded = false

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                shimmer
            case .failed:
                unavailableRow
            case .loaded(let briefing):
                if expanded {
                    expandedCard(briefing)
                } else {
                    collapsedRow(briefing)
                }
            }
        }
        .task(id: payload.dayKey) {
            await loadIfNeeded()
        }
    }

    // MARK: - Loading

    private func loadIfNeeded() async {
        // Once per dayKey: skip when today's briefing is already in hand.
        if let briefing = state.value, briefing.dayKey == payload.dayKey { return }
        expanded = seenDayKey != payload.dayKey
        await fetch()
    }

    private func fetch() async {
        state = .loading
        do {
            let briefing = try await model.api.briefingToday()
            state = .loaded(briefing)
            seenDayKey = payload.dayKey
        } catch {
            model.handle(error)
            state = .failed(TodayStore.message(for: error))
        }
    }

    // MARK: - Expanded

    private func expandedCard(_ briefing: BriefingDTO) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                HStack(spacing: Space.sm) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentPrimary)
                    Text("Morning briefing")
                        .font(.headlineJ)
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { expanded = false }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse briefing")
            }

            ForEach(paragraphs(briefing.content), id: \.self) { paragraph in
                Text(paragraph)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Generated \(ChatDisplay.timeLabel(for: briefing.createdAt))")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
                Spacer(minLength: Space.sm)
                Button("Open chat about today") {
                    model.requestedSection = .chat
                }
                .buttonStyle(.jarvisGhost)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
        .overlay(alignment: .top) { topAccent }
    }

    private func paragraphs(_ content: String) -> [String] {
        content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Collapsed

    private func collapsedRow(_ briefing: BriefingDTO) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { expanded = true }
        } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: "sun.max")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentPrimary)
                Text("Morning briefing · \(firstSentence(briefing.content))")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: Space.sm)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .jarvisCard(padding: Space.md)
        .overlay(alignment: .top) { topAccent }
        .accessibilityLabel("Expand morning briefing")
    }

    private func firstSentence(_ content: String) -> String {
        let flattened = content.replacingOccurrences(of: "\n", with: " ")
        if let end = flattened.firstIndex(where: { ".!?".contains($0) }) {
            return String(flattened[...end])
        }
        return flattened
    }

    // MARK: - Loading / failure states

    private var shimmer: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.bgSubtle)
                    .frame(height: 12)
                    .frame(maxWidth: index == 2 ? 180 : .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
        .overlay(alignment: .top) { topAccent }
        .shimmering()
        .accessibilityLabel("Briefing loading")
    }

    private var unavailableRow: some View {
        HStack(spacing: Space.sm) {
            Text("Briefing unavailable")
                .font(.subheadJ)
                .foregroundStyle(Color.textTertiary)
            Spacer(minLength: Space.sm)
            Button {
                Task { await fetch() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry briefing")
        }
        .jarvisCard(padding: Space.md)
    }

    private var topAccent: some View {
        Capsule()
            .fill(Color.accentSubtle)
            .frame(height: 2)
            .padding(.horizontal, Radius.card)
            .allowsHitTesting(false)
    }
}

// MARK: - Shimmer

/// Slow opacity pulse for placeholder content.
private struct ShimmerModifier: ViewModifier {
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { dimmed = true }
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}
