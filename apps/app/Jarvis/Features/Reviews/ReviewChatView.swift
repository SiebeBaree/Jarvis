import DesignSystem
import JarvisAPI
import Observation
import SwiftUI

// MARK: - Store

/// Minimal chat store for review conversations. Talks to the shared chat
/// stream directly (delta accumulation + action cards). Deliberately
/// independent from Features/Chat, which is built concurrently — a later
/// polish pass can unify the two.
@Observable
@MainActor
final class ReviewChatStore {
    enum Role {
        case user
        case assistant
    }

    struct Message: Identifiable, Equatable {
        let id: String
        let role: Role
        var text: String
    }

    var conversationId: String?
    private(set) var messages: [Message] = []
    private(set) var actions: [ProposedActionDTO] = []
    private(set) var isStreaming = false
    /// Transient "Reading your week…" style line while a tool runs.
    private(set) var toolStatus: String?
    var streamError: String?
    var actionError: String?

    private var model: AppModel?

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    func send(_ text: String) async {
        guard let model, !isStreaming else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(Message(id: UUID().uuidString, role: .user, text: trimmed))
        let assistantId = UUID().uuidString
        messages.append(Message(id: assistantId, role: .assistant, text: ""))
        isStreaming = true
        streamError = nil

        do {
            for try await event in model.api.chatStream(conversationId: conversationId, message: trimmed) {
                switch event {
                case .meta(let id):
                    conversationId = id
                case .delta(let delta):
                    append(delta, to: assistantId)
                case .toolCall(let name, let status):
                    toolStatus = status == "done" || status == "error" ? nil : toolLabel(name)
                case .action(let action):
                    upsert(action)
                case .done:
                    break
                case .error(_, let message):
                    streamError = message
                }
            }
        } catch {
            model.handle(error)
            streamError = TodayStore.message(for: error)
        }

        toolStatus = nil
        isStreaming = false
        // Drop the assistant bubble if the stream produced no text.
        if let index = messages.firstIndex(where: { $0.id == assistantId }), messages[index].text.isEmpty {
            messages.remove(at: index)
        }
    }

    func confirm(_ action: ProposedActionDTO) async {
        guard let model else { return }
        do {
            upsert(try await model.api.confirmAction(id: action.id).action)
            actionError = nil
            model.invalidateToday()
        } catch {
            model.handle(error)
            actionError = TodayStore.message(for: error)
        }
    }

    func reject(_ action: ProposedActionDTO) async {
        guard let model else { return }
        do {
            upsert(try await model.api.rejectAction(id: action.id).action)
            actionError = nil
        } catch {
            model.handle(error)
            actionError = TodayStore.message(for: error)
        }
    }

    private func append(_ delta: String, to messageId: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[index].text += delta
    }

    private func upsert(_ action: ProposedActionDTO) {
        if let index = actions.firstIndex(where: { $0.id == action.id }) {
            actions[index] = action
        } else {
            actions.append(action)
        }
    }

    /// "create_task" → "Working on create task…" style transient label.
    private func toolLabel(_ name: String) -> String {
        let words = name.replacingOccurrences(of: "_", with: " ")
        return "\(words.prefix(1).capitalized + words.dropFirst())…"
    }
}

// MARK: - View

/// Lightweight transcript + input bar for review conversations. Adjustment
/// proposals render as minimal confirm/dismiss cards below the transcript.
struct ReviewChatView: View {
    let store: ReviewChatStore

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    ForEach(store.messages) { message in
                        messageRow(message)
                    }

                    if let toolStatus = store.toolStatus {
                        Text(toolStatus)
                            .font(.subheadJ)
                            .foregroundStyle(Color.textTertiary)
                    } else if store.isStreaming, store.messages.last?.text.isEmpty ?? false {
                        Text("Thinking…")
                            .font(.subheadJ)
                            .foregroundStyle(Color.textTertiary)
                    }

                    if !store.actions.isEmpty {
                        VStack(spacing: Space.md) {
                            ForEach(store.actions) { action in
                                ReviewActionCard(
                                    action: action,
                                    onConfirm: { Task { await store.confirm(action) } },
                                    onDismiss: { Task { await store.reject(action) } },
                                )
                            }
                        }
                    }

                    if let error = store.streamError ?? store.actionError {
                        Text(error)
                            .font(.subheadJ)
                            .foregroundStyle(Color.warning)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, PageMargin.standard)
                .padding(.vertical, Space.lg)
            }
            .onChange(of: transcriptFingerprint) {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
    }

    /// Cheap change token: message count + streamed length + action count.
    private var transcriptFingerprint: String {
        "\(store.messages.count)-\(store.messages.last?.text.count ?? 0)-\(store.actions.count)"
    }

    @ViewBuilder
    private func messageRow(_ message: ReviewChatStore.Message) -> some View {
        switch message.role {
        case .user:
            Text(message.text)
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .background(Color.accentSubtle, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            HStack(alignment: .top, spacing: Space.md) {
                Circle()
                    .fill(Color.accentPrimary)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text("J")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white),
                    )
                    .padding(.top, 1)
                Text(message.text)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderHairline)
                .frame(height: 0.5)
            HStack(spacing: Space.sm) {
                TextField("Reply…", text: $draft, axis: .vertical)
                    .font(.bodyJ)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit(sendDraft)
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(canSend ? Color.accentPrimary : Color.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: 0.5),
            )
            .frame(maxWidth: 560)
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.md)
        }
        .background(Color.bgCanvas)
    }

    private var canSend: Bool {
        !store.isStreaming && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        guard canSend else { return }
        let text = draft
        draft = ""
        Task { await store.send(text) }
    }
}

// MARK: - Minimal action card

/// Compact pending/executed/rejected proposal card (type badge + summary +
/// Confirm/Dismiss). Duplicates the minimal slice of Features/Chat's action
/// card that reviews need; a polish pass will unify them.
private struct ReviewActionCard: View {
    let action: ProposedActionDTO
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    private var badge: String {
        action.toolName.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(badge)
                .font(.captionJ)
                .tracking(0.6)
                .foregroundStyle(Color.accentPrimary)
            Text(action.summary)
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch action.status {
            case "proposed":
                HStack(spacing: Space.sm) {
                    Button("Confirm", action: onConfirm)
                        .buttonStyle(.jarvisPrimary)
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.jarvisGhost)
                }
                .padding(.top, Space.xs)
            case "executed":
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.subheadJ)
                    .foregroundStyle(Color.success)
            case "rejected":
                Text("Dismissed")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            default:
                Text("Expired — data may have changed")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(Space.lg)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(
                    action.status == "proposed" ? Color.accentPrimary.opacity(0.4) : Color.borderHairline,
                    lineWidth: 0.5,
                ),
        )
        // Pending action cards are one of the two shadow exceptions (§B2).
        .shadow(
            color: action.status == "proposed" ? .black.opacity(0.08) : .clear,
            radius: 12,
            y: 2,
        )
    }
}
