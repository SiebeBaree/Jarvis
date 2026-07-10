import DesignSystem
import JarvisAPI
import SwiftUI

/// The Chat screen (§B3): streaming transcript, action cards, suggestion
/// chips, and conversation history. Pass a store to embed a compact chat in
/// another surface (the macOS slide-over); otherwise it owns its own.
struct ChatView: View {
    @Environment(AppModel.self) private var model

    @State private var ownStore = ChatStore()
    @State private var showHistory = false
    @FocusState private var inputFocused: Bool

    private let externalStore: ChatStore?

    init(store: ChatStore? = nil) {
        self.externalStore = store
    }

    private var store: ChatStore { externalStore ?? ownStore }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            inputBar
        }
        .background(Color.bgCanvas)
        .navigationTitle("Jarvis")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New conversation") { store.newConversation() }
                    Button("History") { showHistory = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Chat options")
            }
        }
        .sheet(isPresented: $showHistory) {
            ConversationListView { id in
                Task { await store.loadConversation(id: id) }
            }
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 460)
            #endif
        }
        .task { store.configure(model) }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.isEmpty, !store.isStreaming, !store.isLoadingConversation {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: Space.md) {
                        ForEach(store.items) { item in
                            itemView(item)
                        }
                        if let retryText = store.retryText {
                            retryRow(retryText)
                        }
                        if store.isLoadingConversation {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Space.xl)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, PageMargin.standard)
                    .padding(.vertical, Space.lg)
                }
            }
            .onChange(of: store.revision) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: ChatStore.Item) -> some View {
        switch item.kind {
        case .user(let text):
            Text(text)
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .background(Color.accentSubtle, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)

        case .assistant(let text):
            HStack(alignment: .top, spacing: Space.md) {
                Circle()
                    .fill(Color.accentPrimary)
                    .frame(width: 20, height: 20)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .toolStatus(let name, let done):
            HStack(spacing: Space.sm) {
                if !done {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(ChatDisplay.runningLabel(for: name))
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.leading, 20 + Space.md)

        case .actionCard(let action):
            ActionCardView(
                action: action,
                isBusy: store.actionsInFlight.contains(action.id),
                errorText: store.actionErrors[action.id],
                onConfirm: { Task { await store.confirm(action) } },
                onReject: { Task { await store.reject(action) } },
            )
            .padding(.leading, 20 + Space.md)

        case .systemLine(let text):
            Text(text)
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 20 + Space.md)

        case .errorNote(let text):
            Text(text)
                .font(.subheadJ)
                .foregroundStyle(Color.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.md)
                .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private func retryRow(_ text: String) -> some View {
        Button {
            store.retry()
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                Text("Retry")
            }
        }
        .buttonStyle(.jarvisGhost)
        .accessibilityLabel("Retry sending \(text)")
    }

    // MARK: - Empty state

    private static let suggestions = [
        "Plan my day",
        "How is this week going?",
        "Add a task",
        "I'm feeling off today",
    ]

    private var emptyState: some View {
        VStack(spacing: Space.xl) {
            Circle()
                .fill(Color.accentPrimary)
                .frame(width: 28, height: 28)
            Text("Ask about your day, your week, or what to do next.")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            VStack(spacing: Space.sm) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        store.send(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.subheadJ)
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, Space.lg)
                            .padding(.vertical, Space.sm)
                            .background(Color.bgSurface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, PageMargin.standard)
        .padding(.top, Space.xxxl * 2)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        @Bindable var store = store
        return VStack(spacing: 0) {
            Divider()
                .overlay(Color.borderHairline)
            HStack(alignment: .bottom, spacing: Space.md) {
                TextField("Message Jarvis", text: $store.input, axis: .vertical)
                    .font(.bodyJ)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit { store.send() }
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Color.borderHairline, lineWidth: 0.5),
                    )

                Button {
                    store.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(sendDisabled ? Color.textTertiary : Color.accentPrimary)
                }
                .buttonStyle(.plain)
                .disabled(sendDisabled)
                #if os(macOS)
                .keyboardShortcut(.return, modifiers: .command)
                #endif
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.md)
            .background(Color.bgCanvas)
        }
    }

    private var sendDisabled: Bool {
        store.isStreaming
            || store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
