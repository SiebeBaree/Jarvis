import DesignSystem
import JarvisAPI
import SwiftUI

/// The onboarding interview frame (§B6): full-screen cover (iOS) / large
/// sheet (macOS), 6-dot phase stepper, dimmed transcript above the active
/// card, pinned Continue, and the Plan Proposal Review at the end.
struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var store: OnboardingStore
    @State private var confirmingAbandon = false

    /// `forceFresh` skips the resume probe (Settings → Restart interview).
    init(forceFresh: Bool = false) {
        _store = State(initialValue: OnboardingStore(forceFresh: forceFresh))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
        .task {
            store.configure(model)
            await store.probe()
        }
        .onChange(of: store.phase) { _, newPhase in
            if newPhase == .done { dismiss() }
        }
        .confirmationDialog(
            "Abandon this interview?",
            isPresented: $confirmingAbandon,
            titleVisibility: .visible,
        ) {
            Button("Abandon interview", role: .destructive) {
                Task {
                    await store.abandon()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your answers so far will be discarded.")
        }
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 720, minHeight: 640, idealHeight: 760)
        #endif
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            if store.showsStepper {
                PhaseStepper(currentIndex: store.phaseIndex)
            }
            HStack {
                Spacer()
                overflowMenu
            }
        }
        .padding(.horizontal, PageMargin.standard)
        .padding(.vertical, Space.md)
    }

    private var overflowMenu: some View {
        Menu {
            // The session stays active server-side and resumes via the probe.
            Button("Save & exit") { dismiss() }
            if store.sessionId != nil {
                Button("Abandon interview", role: .destructive) {
                    confirmingAbandon = true
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Interview options")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .probing:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .probeFailed(let message):
            probeFailedCard(message)
        case .landing:
            landing
        case .answering, .thinking:
            interviewScroll
        case .reviewing, .applying:
            PlanReviewView(store: store)
        case .done:
            Color.bgCanvas
        }
    }

    private var interviewScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    transcriptView
                    if store.phase == .answering, let round = store.round {
                        QuestionCardView(round: round, store: store)
                            .id("round-\(round.phaseIndex)-\(round.questions.first?.id ?? "")")
                    } else if store.phase == .thinking {
                        ThinkingView(error: store.answerError) {
                            Task { await store.retryAnswer() }
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, PageMargin.standard)
                .padding(.vertical, Space.xl)
            }
            .onChange(of: store.transcript.count) {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.phase == .answering {
                continueBar
            }
        }
    }

    private var continueBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderHairline)
                .frame(height: 0.5)
            Button {
                Task { await store.submit() }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.jarvisPrimary)
            .disabled(!store.canContinue)
            .opacity(store.canContinue ? 1 : 0.5)
            .frame(maxWidth: 560)
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.md)
        }
        .background(Color.bgCanvas)
    }

    // MARK: - Transcript (dimmed, non-interactive scroll-back)

    @ViewBuilder
    private var transcriptView: some View {
        if !store.transcript.isEmpty {
            VStack(alignment: .leading, spacing: Space.lg) {
                ForEach(store.transcript) { entry in
                    switch entry.kind {
                    case .phaseDivider(let name):
                        phaseDivider(name)
                    case .qa(let question, let answer, let isFollowUp):
                        transcriptRow(question: question, answer: answer, isFollowUp: isFollowUp)
                    }
                }
            }
        }
    }

    private func phaseDivider(_ name: String) -> some View {
        HStack(spacing: Space.md) {
            Rectangle().fill(Color.borderHairline).frame(height: 0.5)
            Text(name.uppercased())
                .font(.captionJ)
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
                .fixedSize()
            Rectangle().fill(Color.borderHairline).frame(height: 0.5)
        }
        .padding(.vertical, Space.xs)
    }

    private func transcriptRow(question: String, answer: String, isFollowUp: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(isFollowUp ? "↳ \(question)" : question)
                .font(.subheadJ)
            Text(answer)
                .font(.subheadJ)
                .fontWeight(.medium)
        }
        .foregroundStyle(Color.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Landing (no draft)

    private var landing: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Let's build your plan")
                    .font(.title1J)
                    .foregroundStyle(Color.textPrimary)
                Text(
                    """
                    I'll ask about your life, values, and what you want the \
                    next 12 weeks to look like. From your answers I'll draft \
                    a plan — goals, weekly tactics, habits, and tasks. \
                    Nothing is created until you review and approve it.
                    """
                )
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                Text("This takes 15–30 minutes; you can leave and resume anytime.")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
                if let error = store.startError {
                    Text(error)
                        .font(.subheadJ)
                        .foregroundStyle(Color.warning)
                }
                Button {
                    Task { await store.begin() }
                } label: {
                    Group {
                        if store.isStarting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Text("Begin")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.jarvisPrimary)
                .disabled(store.isStarting)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisCard(padding: Space.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PageMargin.standard)
            .padding(.top, Space.xxxl)
        }
    }

    // MARK: - Probe failure

    private func probeFailedCard(_ message: String) -> some View {
        VStack(spacing: Space.lg) {
            Text(message)
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await store.retryProbe() }
            }
            .buttonStyle(.jarvisSecondary)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(PageMargin.standard)
    }
}

// MARK: - Phase stepper (6 dots: filled = past, accent = current, hollow = future)

private struct PhaseStepper: View {
    let currentIndex: Int

    var body: some View {
        VStack(spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                ForEach(0..<OnboardingStore.phaseNames.count, id: \.self) { index in
                    dot(for: index)
                }
            }
            Text(OnboardingStore.phaseNames[min(max(currentIndex, 0), OnboardingStore.phaseNames.count - 1)])
                .font(.captionJ)
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Phase \(currentIndex + 1) of \(OnboardingStore.phaseNames.count): \(OnboardingStore.phaseNames[min(max(currentIndex, 0), OnboardingStore.phaseNames.count - 1)])")
    }

    @ViewBuilder
    private func dot(for index: Int) -> some View {
        if index < currentIndex {
            Circle()
                .fill(Color.textTertiary)
                .frame(width: 7, height: 7)
        } else if index == currentIndex {
            Circle()
                .fill(Color.accentPrimary)
                .frame(width: 8, height: 8)
        } else {
            Circle()
                .strokeBorder(Color.borderStrong, lineWidth: 1)
                .frame(width: 7, height: 7)
        }
    }
}
