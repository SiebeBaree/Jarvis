import DesignSystem
import JarvisAPI
import SwiftUI

/// Conversation history sheet: reverse-chron list, tap to reopen, swipe to
/// delete (with confirmation).
struct ConversationListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let onSelect: (String) -> Void

    @State private var state: LoadState<[ConversationSummaryDTO]> = .idle
    @State private var pendingDelete: ConversationSummaryDTO?

    var body: some View {
        NavigationStack {
            content
                .background(Color.bgCanvas)
                .navigationTitle("History")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            MemoryView()
                        } label: {
                            Image(systemName: "brain")
                        }
                        .accessibilityLabel("What J.A.R.V.I.S. knows")
                    }
                }
        }
        .task { await load() }
        .confirmationDialog(
            "Delete this conversation?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } },
            ),
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) {
                if let conversation = pendingDelete {
                    Task { await delete(conversation) }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: Space.lg) {
                Text(message)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textSecondary)
                Button("Retry") { Task { await load() } }
                    .buttonStyle(.jarvisSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let conversations):
            if conversations.isEmpty {
                Text("No conversations yet")
                    .font(.bodyJ)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(conversations) { conversation in
                        row(conversation)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Color.borderHairline)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    pendingDelete = conversation
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func row(_ conversation: ConversationSummaryDTO) -> some View {
        Button {
            onSelect(conversation.id)
            dismiss()
        } label: {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title ?? ChatDisplay.kindLabel(for: conversation))
                        .font(.headlineJ)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(ChatDisplay.relativeLabel(for: conversation.updatedAt))
                        .font(.captionJ)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer(minLength: Space.sm)
                if conversation.kind != "chat" {
                    TagChip(ChatDisplay.kindLabel(for: conversation))
                }
            }
            .frame(minHeight: RowHeight.standard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let response = try await model.api.conversations()
            // Reverse-chron by last activity.
            let sorted = response.conversations.sorted {
                (ChatDisplay.date(from: $0.updatedAt) ?? .distantPast)
                    > (ChatDisplay.date(from: $1.updatedAt) ?? .distantPast)
            }
            state = .loaded(sorted)
        } catch {
            model.handle(error)
            state = .failed(TodayStore.message(for: error))
        }
    }

    private func delete(_ conversation: ConversationSummaryDTO) async {
        do {
            _ = try await model.api.deleteConversation(id: conversation.id)
            if case .loaded(var conversations) = state {
                conversations.removeAll { $0.id == conversation.id }
                state = .loaded(conversations)
            }
        } catch {
            model.handle(error)
            state = .failed(TodayStore.message(for: error))
        }
    }
}
