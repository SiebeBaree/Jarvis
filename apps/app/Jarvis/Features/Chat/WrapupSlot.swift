import DesignSystem
import JarvisAPI
import SwiftUI

/// Evening wrap-up banner on Today (§B3, Today item 8): visible from 20:00
/// (or once everything is done), shows the near-final score plus one AI
/// sentence, and collapses for the rest of the day via "Done for today".
struct WrapupSlot: View {
    @Environment(AppModel.self) private var model

    let payload: DayPayload

    /// DayKey the user wrapped — collapses the banner for the rest of that day.
    @AppStorage("wrapupDoneDayKey") private var wrappedDayKey = ""

    @State private var sentence: LoadState<BriefingDTO> = .idle

    var body: some View {
        if isVisible {
            if wrappedDayKey == payload.dayKey {
                wrappedLine
            } else {
                card
                    .task(id: fingerprint) { await fetchSentence() }
            }
        }
    }

    // MARK: - Visibility

    private var isVisible: Bool {
        isEveningNow || allDone
    }

    private var isEveningNow: Bool {
        // From 20:00, including the post-midnight stretch that still counts
        // for this dayKey (3 AM boundary).
        let hour = Calendar.current.component(.hour, from: .now)
        return hour >= 20 || DayKeyMath.isLateNight()
    }

    /// All tasks done and all habits at full credit — vacuously false when
    /// the day has nothing to do at all.
    private var allDone: Bool {
        guard !(payload.tasksDue.isEmpty && payload.habits.isEmpty) else { return false }
        let tasksDone = payload.overdueTasks.isEmpty
            && payload.tasksDue.allSatisfy { $0.status == .done }
        let habitsFull = payload.habits.allSatisfy { $0.credit >= 1 }
        return tasksDone && habitsFull
    }

    /// Refetch key: the endpoint is fingerprint-cached server-side, so
    /// refetching whenever the payload meaningfully changes is cheap.
    private var fingerprint: String {
        let score = payload.score
        return [
            payload.dayKey,
            score.total.map { String($0) } ?? "-",
            score.taskPoints.map { String($0) } ?? "-",
            score.habitPoints.map { String($0) } ?? "-",
            payload.mood.map { String($0.value) } ?? "-",
        ].joined(separator: "|")
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Day wrap-up")
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let total = payload.score.total {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Text("\(Int(total.rounded()))")
                            .font(.title2J.monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                        Text("near-final")
                            .font(.captionJ)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            sentenceView

            if payload.mood == nil {
                Text("Don't forget to set your feel score.")
                    .font(.captionJ)
                    .foregroundStyle(Color.textSecondary)
            }

            Button("Done for today") {
                withAnimation(.easeOut(duration: 0.2)) {
                    wrappedDayKey = payload.dayKey
                }
            }
            .buttonStyle(.jarvisSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    @ViewBuilder
    private var sentenceView: some View {
        switch sentence {
        case .idle, .loading:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgSubtle)
                .frame(height: 12)
                .frame(maxWidth: 260, alignment: .leading)
                .accessibilityHidden(true)
        case .failed:
            // Quiet failure — the score alone still makes the banner useful.
            EmptyView()
        case .loaded(let wrapup):
            Text(wrapup.content)
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Wrapped

    private var wrappedLine: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
            Text("Day wrapped")
                .font(.subheadJ)
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .padding(.vertical, Space.xs)
    }

    // MARK: - Data

    private func fetchSentence() async {
        sentence = .loading
        do {
            sentence = .loaded(try await model.api.wrapupToday())
        } catch {
            model.handle(error)
            sentence = .failed(TodayStore.message(for: error))
        }
    }
}
