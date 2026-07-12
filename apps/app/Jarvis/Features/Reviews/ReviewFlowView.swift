import DesignSystem
import JarvisAPI
import SwiftUI

/// Which review flow to run: the weekly check-in or the week-13 block
/// retrospective (§B3 Weekly Review / Week 13).
enum ReviewKind {
    case weekly
    case block
}

/// Shared presentation: full-screen cover on iOS, large sheet on macOS.
extension View {
    func reviewFlowCover(isPresented: Binding<Bool>, kind: ReviewKind) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented) {
            ReviewFlowView(kind: kind)
                .frame(minWidth: 680, idealWidth: 720, minHeight: 640, idealHeight: 760)
        }
        #else
        fullScreenCover(isPresented: isPresented) {
            ReviewFlowView(kind: kind)
        }
        #endif
    }
}

/// Three-phase review flow (§B3): recap deck → AI conversation (adjustment
/// proposals as action cards) → close screen with the stored outcome. The
/// block kind chains into re-onboarding for the next block.
struct ReviewFlowView: View {
    let kind: ReviewKind

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case recap
        case starting
        case conversation
        case closing
        case outcome(ReviewOutcomeDTO)
    }

    @State private var phase: Phase = .recap
    @State private var chat = ReviewChatStore()
    @State private var weekNumber: Int?
    @State private var resumedExisting = false
    @State private var flowError: String?
    @State private var showNextBlockPlanning = false

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgCanvas)
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
        }
        .task { chat.configure(model) }
        .interactiveDismissDisabled(isConversationPhase)
    }

    private var title: String {
        switch kind {
        case .weekly:
            if let weekNumber { return "Week \(weekNumber) review" }
            return "Weekly review"
        case .block:
            return "Block retrospective"
        }
    }

    private var isConversationPhase: Bool {
        if case .conversation = phase { return true }
        return false
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            switch phase {
            case .recap, .starting:
                Button("Close") { dismiss() }
            case .conversation:
                // The server keeps the conversation open — resuming later is fine.
                Button("Later") { dismiss() }
            case .closing, .outcome:
                EmptyView().hidden()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isConversationPhase {
                Button("Finish review") {
                    Task { await finish() }
                }
                .disabled(chat.isStreaming || chat.conversationId == nil)
            }
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .recap:
            ReviewRecapDeck(kind: kind) {
                Task { await startConversation() }
            }
        case .starting:
            VStack(spacing: Space.lg) {
                if let flowError {
                    Text(flowError)
                        .font(.bodyJ)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await startConversation() }
                    }
                    .buttonStyle(.jarvisSecondary)
                } else {
                    ProgressView()
                    Text("Preparing your review…")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(PageMargin.standard)
        case .conversation:
            VStack(spacing: 0) {
                if resumedExisting {
                    Text("Resuming your open review")
                        .font(.captionJ)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.top, Space.sm)
                }
                if let flowError {
                    Text(flowError)
                        .font(.subheadJ)
                        .foregroundStyle(Color.warning)
                        .padding(.top, Space.sm)
                }
                ReviewChatView(store: chat)
            }
        case .closing:
            VStack(spacing: Space.lg) {
                ProgressView()
                Text("Summarizing your week…")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            }
        case .outcome(let outcome):
            outcomeView(outcome)
        }
    }

    // MARK: - Actions

    private func startConversation() async {
        phase = .starting
        flowError = nil
        do {
            let response: ReviewStartResponse
            switch kind {
            case .weekly:
                response = try await model.api.startWeeklyReview(weekNumber: nil)
            case .block:
                response = try await model.api.startBlockReview()
            }
            weekNumber = response.conversation.weekNumber
            resumedExisting = response.existing
            chat.conversationId = response.conversation.id
            phase = .conversation
            await chat.send("Let's review.")
        } catch {
            model.handle(error)
            flowError = TodayStore.message(for: error)
        }
    }

    private func finish() async {
        guard let conversationId = chat.conversationId else { return }
        phase = .closing
        flowError = nil
        do {
            let response = try await model.api.closeReview(conversationId: conversationId)
            phase = .outcome(response.outcome)
        } catch {
            model.handle(error)
            flowError = TodayStore.message(for: error)
            phase = .conversation
        }
    }

    // MARK: - Outcome screen

    private func outcomeView(_ outcome: ReviewOutcomeDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(closedTitle)
                        .font(.title1J)
                        .foregroundStyle(Color.textPrimary)
                    Text("Here's what we captured.")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textSecondary)
                }

                outcomeSection("Wins", items: outcome.wins, icon: "checkmark.circle", tint: .success)
                outcomeSection("Struggles", items: outcome.struggles, icon: "circle.slash", tint: .warning)
                outcomeSection("Adjustments", items: outcome.adjustments, icon: "arrow.triangle.2.circlepath", tint: .accentPrimary)

                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader("Focus next week")
                    Text(outcome.focusNextWeek)
                        .font(.bodyJ)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .jarvisCard()
                }

                VStack(spacing: Space.sm) {
                    if kind == .block {
                        Button {
                            showNextBlockPlanning = true
                        } label: {
                            Text("Plan the next block")
                                .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(.jarvisPrimary)
                    }
                    Button {
                        model.invalidateToday()
                        dismiss()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(kind == .block ? AnyButtonStyle(.jarvisSecondary) : AnyButtonStyle(.jarvisPrimary))
                }
                .padding(.top, Space.sm)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(PageMargin.standard)
            .padding(.vertical, Space.xl)
        }
        .nextBlockPlanningCover(isPresented: $showNextBlockPlanning) {
            // Retro → re-onboarding chain finished (or was abandoned):
            // refresh Today and close the review flow behind it.
            model.invalidateToday()
            dismiss()
        }
    }

    private var closedTitle: String {
        switch kind {
        case .weekly:
            if let weekNumber { return "Week \(weekNumber) closed" }
            return "Week closed"
        case .block:
            return "Block closed"
        }
    }

    @ViewBuilder
    private func outcomeSection(_ title: String, items: [String], icon: String, tint: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(title)
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                            Image(systemName: icon)
                                .font(.system(size: 12))
                                .foregroundStyle(tint)
                            Text(item)
                                .font(.bodyJ)
                                .foregroundStyle(Color.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .jarvisCard()
            }
        }
    }
}

// MARK: - Helpers

/// Type-erased button style so the Done button can switch primary/secondary.
private struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init(_ style: some ButtonStyle) {
        makeBodyClosure = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}

/// Presents next-block planning (§B3 Week 13): the manual setup wizard,
/// with a completion when it dismisses.
private struct NextBlockPlanningModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            SetupWizardView()
        }
        #else
        content.fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) {
            SetupWizardView()
        }
        #endif
    }
}

private extension View {
    func nextBlockPlanningCover(isPresented: Binding<Bool>, onDismiss: @escaping () -> Void) -> some View {
        modifier(NextBlockPlanningModifier(isPresented: isPresented, onDismiss: onDismiss))
    }
}
