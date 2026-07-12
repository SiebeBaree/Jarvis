import DesignSystem
import JarvisAPI
import SwiftUI

/// The manual setup wizard: you author your plan (areas → block → goals →
/// habits → improvement areas), then optionally talk to J.A.R.V.I.S. so it
/// learns who you are. Replaces the old AI onboarding interview.
struct SetupWizardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var store = SetupWizardStore()
    @State private var confirmingClose = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if store.step != .welcome, store.step != .done {
                    progressDots
                        .padding(.top, Space.md)
                }
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .background(Color.bgCanvas)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle(store.step.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if store.applied || store.step == .welcome {
                            dismiss()
                        } else {
                            confirmingClose = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Leave setup?",
                isPresented: $confirmingClose,
                titleVisibility: .visible,
            ) {
                Button("Leave without saving", role: .destructive) { dismiss() }
                Button("Keep setting up", role: .cancel) {}
            } message: {
                Text("Nothing has been created yet — your drafts will be lost.")
            }
        }
        .interactiveDismissDisabled(!store.applied && store.step != .welcome)
        .task { store.configure(model) }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 700)
        #endif
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch store.step {
        case .welcome: SetupWelcomeStep()
        case .areas: SetupAreasStep(store: store)
        case .block: SetupBlockStep(store: store)
        case .goals: SetupGoalsStep(store: store)
        case .habits: SetupHabitsStep(store: store)
        case .improve: SetupImproveStep(store: store)
        case .seed: SetupSeedStep()
        case .done: SetupDoneStep()
        }
    }

    private var progressDots: some View {
        HStack(spacing: Space.sm) {
            ForEach(SetupWizardStore.progressSteps, id: \.self) { step in
                Circle()
                    .fill(dotColor(step))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("Step \(stepNumber) of \(SetupWizardStore.progressSteps.count)")
    }

    private var stepNumber: Int {
        (SetupWizardStore.progressSteps.firstIndex(of: store.step) ?? 0) + 1
    }

    private func dotColor(_ step: SetupWizardStore.Step) -> Color {
        guard let current = SetupWizardStore.progressSteps.firstIndex(of: store.step),
              let index = SetupWizardStore.progressSteps.firstIndex(of: step) else {
            return .borderHairline
        }
        return index <= current ? .accentPrimary : .borderHairline
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Space.sm) {
            if let error = store.applyError {
                Text(error)
                    .font(.subheadJ)
                    .foregroundStyle(Color.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if store.step != .welcome, store.step != .done, !backHidden {
                    Button("Back") { store.back() }
                        .buttonStyle(.jarvisGhost)
                }
                Spacer()
                primaryButton
            }
        }
        .padding(.horizontal, PageMargin.standard)
        .padding(.vertical, Space.lg)
    }

    /// Once the plan is applied (before the seed step), Back would desync
    /// drafts from reality — hide it.
    private var backHidden: Bool {
        store.applied && (store.step == .seed || store.step == .done)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch store.step {
        case .welcome:
            Button("Set up my plan") { store.next() }
                .buttonStyle(.jarvisPrimary)

        case .improve:
            // Applying happens here so the seeding chat sees the real plan.
            Button {
                Task {
                    if await store.apply() { store.next() }
                }
            } label: {
                if store.isApplying {
                    ProgressView().controlSize(.small)
                } else {
                    Text(store.applyError == nil ? "Create my plan" : "Retry")
                }
            }
            .buttonStyle(.jarvisPrimary)
            .disabled(store.isApplying)

        case .seed:
            Button("Continue") { store.next() }
                .buttonStyle(.jarvisPrimary)

        case .done:
            Button("Start using Jarvis") {
                model.invalidateToday()
                dismiss()
            }
            .buttonStyle(.jarvisPrimary)

        default:
            Button("Next") { store.next() }
                .buttonStyle(.jarvisPrimary)
                .disabled(!store.canGoNext)
        }
    }
}

/// Presents the setup wizard platform-appropriately: full-screen cover on
/// iOS, large sheet on macOS. (Replaces the old onboardingInterviewCover.)
private struct SetupWizardPresenterModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content.sheet(isPresented: $isPresented) {
            SetupWizardView()
        }
        #else
        content.fullScreenCover(isPresented: $isPresented) {
            SetupWizardView()
        }
        #endif
    }
}

extension View {
    func setupWizardCover(isPresented: Binding<Bool>) -> some View {
        modifier(SetupWizardPresenterModifier(isPresented: isPresented))
    }
}
