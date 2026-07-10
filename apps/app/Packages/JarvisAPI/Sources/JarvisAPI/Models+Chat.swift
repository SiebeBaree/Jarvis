import Foundation

// Stage 3+4 DTOs: chat conversations, streaming events, proposed action
// cards, briefings, and reviews.

// MARK: - Conversations

public struct ConversationSummaryDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let kind: String // chat | weekly_review | block_review | ...
    public let title: String?
    public let blockId: String?
    public let weekNumber: Int?
    public let hasOutcome: Bool
    public let updatedAt: String
    public let createdAt: String
}

public struct ConversationDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let kind: String
    public let title: String?
    public let blockId: String?
    public let weekNumber: Int?
    public let outcome: ReviewOutcomeDTO?
    public let createdAt: String
    public let updatedAt: String
}

public struct ConversationListResponse: Codable, Sendable {
    public let conversations: [ConversationSummaryDTO]
}

// MARK: - Messages

/// One part of a message body. Discriminated on `type` server-side; unknown
/// types decode to `.unknown` so newer servers don't break older clients.
/// The arbitrary-JSON `args`/`result` payloads are intentionally not decoded —
/// the UI only renders the tool name / call linkage.
public enum MessagePart: Codable, Sendable, Equatable {
    case text(String)
    case toolCall(callId: String, name: String)
    case toolResult(callId: String)
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, callId, name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "tool_call":
            self = .toolCall(
                callId: try container.decode(String.self, forKey: .callId),
                name: try container.decode(String.self, forKey: .name),
            )
        case "tool_result":
            self = .toolResult(callId: try container.decode(String.self, forKey: .callId))
        default:
            self = .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolCall(let callId, let name):
            try container.encode("tool_call", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(name, forKey: .name)
        case .toolResult(let callId):
            try container.encode("tool_result", forKey: .type)
            try container.encode(callId, forKey: .callId)
        case .unknown(let type):
            try container.encode(type, forKey: .type)
        }
    }
}

public struct MessageDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let role: String // user | assistant | tool
    public let parts: [MessagePart]
    public let createdAt: String
}

// MARK: - Proposed actions

/// An action card the assistant proposed during chat. `args`/`result` are
/// arbitrary JSON and intentionally not decoded (not needed by the UI).
public struct ProposedActionDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let conversationId: String
    public let messageId: String
    public let toolName: String
    public let summary: String
    public let status: String // proposed | executed | rejected | expired
    public let createdAt: String
    public let resolvedAt: String?
}

public struct ActionResponse: Codable, Sendable {
    public let action: ProposedActionDTO
}

public struct ConversationDetailResponse: Codable, Sendable {
    public let conversation: ConversationDTO
    public let messages: [MessageDTO]
    public let actions: [ProposedActionDTO]
}

// MARK: - Reviews

public struct ReviewOutcomeDTO: Codable, Sendable, Equatable {
    public let wins: [String]
    public let struggles: [String]
    public let adjustments: [String]
    public let focusNextWeek: String
}

public struct ReviewStartResponse: Codable, Sendable {
    public let conversation: ConversationDTO
    /// True when an already-open review conversation was returned instead of
    /// a freshly created one.
    public let existing: Bool
}

public struct ReviewCloseResponse: Codable, Sendable {
    public let outcome: ReviewOutcomeDTO
}

// MARK: - Briefings

public struct BriefingDTO: Codable, Sendable, Equatable {
    public let dayKey: DayKey
    public let kind: String // briefing | wrapup
    public let content: String
    public let createdAt: String
}

// MARK: - Chat stream events

/// A parsed chat SSE event. Unknown event names map to nil so the server can
/// add event types without breaking older clients.
public enum ChatStreamEvent: Sendable, Equatable {
    case meta(conversationId: String)
    case delta(String)
    case toolCall(name: String, status: String)
    case action(ProposedActionDTO)
    case done(messageId: String, conversationId: String)
    case error(code: String, message: String)

    private struct MetaPayload: Decodable {
        let conversationId: String
    }

    private struct DeltaPayload: Decodable {
        let text: String
    }

    private struct ToolCallPayload: Decodable {
        let name: String
        let status: String
    }

    private struct DonePayload: Decodable {
        let messageId: String
        let conversationId: String
    }

    private struct ErrorPayload: Decodable {
        let code: String
        let message: String
    }

    /// Nil for unknown event names; throws when a known event carries
    /// malformed JSON.
    public init?(sseEvent: SSEEvent) throws {
        let decoder = JSONDecoder()
        let data = Data(sseEvent.data.utf8)
        switch sseEvent.event {
        case "meta":
            self = .meta(conversationId: try decoder.decode(MetaPayload.self, from: data).conversationId)
        case "message_delta":
            self = .delta(try decoder.decode(DeltaPayload.self, from: data).text)
        case "tool_call":
            let payload = try decoder.decode(ToolCallPayload.self, from: data)
            self = .toolCall(name: payload.name, status: payload.status)
        case "action":
            self = .action(try decoder.decode(ProposedActionDTO.self, from: data))
        case "message_done":
            let payload = try decoder.decode(DonePayload.self, from: data)
            self = .done(messageId: payload.messageId, conversationId: payload.conversationId)
        case "error":
            let payload = try decoder.decode(ErrorPayload.self, from: data)
            self = .error(code: payload.code, message: payload.message)
        default:
            return nil
        }
    }
}
