import Foundation
import JarvisAPI
import Observation

/// Feature store for a chat conversation: the transcript, the live SSE
/// stream, and action-card confirm/reject. One store per surface — the Chat
/// tab and the macOS slide-over each own an independent instance.
@Observable
@MainActor
final class ChatStore {
    enum ItemKind {
        case user(String)
        case assistant(String)
        /// Transient tool status line ("Reading your week…"). Removed once the
        /// next text delta arrives — it collapses into the finished message.
        case toolStatus(name: String, done: Bool)
        case actionCard(ProposedActionDTO)
        /// Subtle system line (tool-role messages when replaying history).
        case systemLine(String)
        case errorNote(String)
    }

    struct Item: Identifiable {
        let id: String
        var kind: ItemKind

        init(id: String = UUID().uuidString, kind: ItemKind) {
            self.id = id
            self.kind = kind
        }
    }

    private(set) var conversationId: String?
    private(set) var items: [Item] = []
    private(set) var isStreaming = false
    private(set) var isLoadingConversation = false
    var input = ""

    /// Kind used when the next send creates a NEW conversation
    /// ("seeding" for the setup wizard's get-to-know-you chat).
    var newConversationKind: String?

    /// Last user text whose stream failed — powers the retry affordance.
    private(set) var retryText: String?
    /// Action ids with a confirm/reject request in flight.
    private(set) var actionsInFlight: Set<String> = []
    /// Inline per-card error messages from failed confirm/reject calls.
    private(set) var actionErrors: [String: String] = [:]

    /// Bumped on every transcript mutation so the view can auto-scroll.
    private(set) var revision = 0

    private var model: AppModel?
    private var streamTask: Task<Void, Never>?

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    var isEmpty: Bool { items.isEmpty }

    // MARK: - Sending

    /// Sends the given text (or the input field). No-op while a stream runs.
    func send(_ overrideText: String? = nil) {
        let text = (overrideText ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, let model else { return }
        if overrideText == nil { input = "" }
        retryText = nil
        append(.user(text))
        isStreaming = true

        streamTask = Task {
            var assistantItemId: String?
            var toolStatusIds: [String] = []
            do {
                let kind = conversationId == nil ? newConversationKind : nil
                for try await event in model.api.chatStream(
                    conversationId: conversationId,
                    message: text,
                    kind: kind,
                ) {
                    switch event {
                    case .meta(let cid):
                        conversationId = cid

                    case .delta(let chunk):
                        // A delta collapses any finished tool-status lines.
                        removeDoneToolStatuses(&toolStatusIds)
                        if let id = assistantItemId, let index = index(of: id),
                           case .assistant(let existing) = items[index].kind {
                            items[index].kind = .assistant(existing + chunk)
                        } else {
                            let item = Item(kind: .assistant(chunk))
                            assistantItemId = item.id
                            items.append(item)
                        }
                        revision += 1

                    case .toolCall(let name, let status):
                        if status == "running" {
                            removeDoneToolStatuses(&toolStatusIds)
                            let item = Item(kind: .toolStatus(name: name, done: false))
                            toolStatusIds.append(item.id)
                            items.append(item)
                        } else {
                            for id in toolStatusIds {
                                if let index = index(of: id),
                                   case .toolStatus(let n, false) = items[index].kind, n == name {
                                    items[index].kind = .toolStatus(name: n, done: true)
                                }
                            }
                        }
                        revision += 1

                    case .action(let action):
                        removeDoneToolStatuses(&toolStatusIds)
                        append(.actionCard(action))

                    case .done:
                        // A message finished; further deltas start a new bubble.
                        assistantItemId = nil
                        removeDoneToolStatuses(&toolStatusIds)

                    case .error(_, let message):
                        append(.errorNote(message))
                        retryText = text
                    }
                }
            } catch {
                model.handle(error)
                append(.errorNote(TodayStore.message(for: error)))
                retryText = text
            }
            // Never leave orphaned running spinners behind.
            for id in toolStatusIds { removeItem(id: id) }
            isStreaming = false
            revision += 1
        }
    }

    /// Re-sends the last failed message.
    func retry() {
        guard let text = retryText else { return }
        send(text)
    }

    // MARK: - Actions

    func confirm(_ action: ProposedActionDTO) async {
        await resolve(action) { try await $0.confirmAction(id: action.id) }
    }

    func reject(_ action: ProposedActionDTO) async {
        await resolve(action) { try await $0.rejectAction(id: action.id) }
    }

    private func resolve(
        _ action: ProposedActionDTO,
        _ operation: (APIClient) async throws -> ActionResponse,
    ) async {
        guard let model, !actionsInFlight.contains(action.id) else { return }
        actionsInFlight.insert(action.id)
        actionErrors[action.id] = nil
        do {
            let response = try await operation(model.api)
            replaceAction(response.action)
            model.invalidateToday()
        } catch {
            model.handle(error)
            actionErrors[action.id] = TodayStore.message(for: error)
        }
        actionsInFlight.remove(action.id)
        revision += 1
    }

    private func replaceAction(_ action: ProposedActionDTO) {
        for index in items.indices {
            if case .actionCard(let existing) = items[index].kind, existing.id == action.id {
                items[index].kind = .actionCard(action)
            }
        }
    }

    // MARK: - History

    /// Replaces the transcript with a stored conversation.
    func loadConversation(id: String) async {
        guard let model else { return }
        streamTask?.cancel()
        isStreaming = false
        retryText = nil
        actionErrors = [:]
        conversationId = id
        isLoadingConversation = true
        items = []
        do {
            let detail = try await model.api.conversation(id: id)
            items = Self.rebuild(from: detail)
        } catch {
            model.handle(error)
            items = [Item(kind: .errorNote(TodayStore.message(for: error)))]
        }
        isLoadingConversation = false
        revision += 1
    }

    func newConversation() {
        streamTask?.cancel()
        isStreaming = false
        conversationId = nil
        items = []
        retryText = nil
        actionErrors = [:]
        actionsInFlight = []
        revision += 1
    }

    /// Rebuilds transcript items from a stored conversation: text parts become
    /// bubbles, tool-role messages a subtle system line, and each message's
    /// actions attach right after it (cards render their persisted state).
    static func rebuild(from detail: ConversationDetailResponse) -> [Item] {
        // callId → tool name, so tool-role results can name their tool.
        var toolNames: [String: String] = [:]
        for message in detail.messages {
            for part in message.parts {
                if case .toolCall(let callId, let name) = part {
                    toolNames[callId] = name
                }
            }
        }

        let actionsByMessage = Dictionary(grouping: detail.actions, by: \.messageId)
        var result: [Item] = []
        for message in detail.messages {
            switch message.role {
            case "user":
                for part in message.parts {
                    if case .text(let text) = part, !text.isEmpty {
                        result.append(Item(kind: .user(text)))
                    }
                }
            case "assistant":
                let text = message.parts
                    .compactMap { if case .text(let t) = $0 { t } else { nil } }
                    .joined(separator: "\n\n")
                if !text.isEmpty {
                    result.append(Item(kind: .assistant(text)))
                }
                // .toolCall parts render nothing — cards come from `actions`.
            case "tool":
                for part in message.parts {
                    if case .toolResult(let callId) = part {
                        let label = toolNames[callId].map(ChatDisplay.doneLabel(for:)) ?? "Looked something up"
                        result.append(Item(kind: .systemLine(label)))
                    }
                }
            default:
                break
            }
            for action in actionsByMessage[message.id] ?? [] {
                result.append(Item(kind: .actionCard(action)))
            }
        }
        return result
    }

    // MARK: - Item helpers

    private func append(_ kind: ItemKind) {
        items.append(Item(kind: kind))
        revision += 1
    }

    private func index(of id: String) -> Int? {
        items.firstIndex { $0.id == id }
    }

    private func removeItem(id: String) {
        items.removeAll { $0.id == id }
    }

    private func removeDoneToolStatuses(_ ids: inout [String]) {
        for id in ids {
            if let index = index(of: id), case .toolStatus(_, true) = items[index].kind {
                items.remove(at: index)
            }
        }
        ids.removeAll { id in
            !items.contains { $0.id == id }
        }
    }
}
