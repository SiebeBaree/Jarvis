import DesignSystem
import JarvisAPI
import SwiftUI

/// Today's weekly check-in prompt: shown when at least one improvement area
/// has no photo this week. The in-app replacement for a push notification.
struct CheckinPromptCard: View {
    @Environment(AppModel.self) private var model

    @State private var store = ImproveStore()
    @State private var showCheckinFlow = false

    var body: some View {
        Group {
            if let response = store.response, response.anyDueThisWeek {
                card(dueCount: store.dueAreas.count)
            }
        }
        .task {
            store.configure(model)
            await store.load()
        }
        .onChange(of: model.todayRevision) {
            Task { await store.load() }
        }
        .sheet(isPresented: $showCheckinFlow, onDismiss: {
            Task { await store.load() }
        }) {
            CheckinFlowView(store: store)
        }
    }

    private func card(dueCount: Int) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: "camera")
                .font(.system(size: 15))
                .foregroundStyle(Color.accentPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly check-in")
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Text("\(dueCount) improvement area\(dueCount == 1 ? "" : "s") due a photo this week")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Space.sm)
            Button("Check in") { showCheckinFlow = true }
                .buttonStyle(.jarvisPrimary)
        }
        .padding(Space.lg)
        .background(Color.accentSubtle.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.accentPrimary.opacity(0.35), lineWidth: 0.5),
        )
    }
}
