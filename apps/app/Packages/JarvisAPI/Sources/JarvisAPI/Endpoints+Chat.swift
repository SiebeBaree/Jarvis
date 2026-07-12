import Foundation

// Stage 3+4 endpoints: streaming chat, conversations, action cards,
// briefings, reviews.

private struct ChatRequest: Encodable, Sendable {
    let conversationId: String?
    let message: String
    /// Kind for a NEW conversation ("chat" | "seeding"); ignored when
    /// conversationId is set.
    let kind: String?

    // Encode conversationId explicitly so a nil becomes JSON null rather than
    // an absent key (the server accepts either; null is the documented shape).
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(kind, forKey: .kind)
    }

    private enum CodingKeys: String, CodingKey {
        case conversationId, message, kind
    }
}

private struct WeeklyReviewStartRequest: Encodable, Sendable {
    let weekNumber: Int?
}

extension APIClient {
    // Chat

    /// Streams a chat turn. HTTP errors before the stream opens (including
    /// 401) surface as a thrown APIClientError from the first iteration.
    /// Cancelling the consuming task tears down the connection.
    public nonisolated func chatStream(
        conversationId: String?,
        message: String,
        kind: String? = nil,
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var (request, session) = try await self.makeRequest(
                        method: "POST",
                        path: "/ai/chat",
                        body: ChatRequest(conversationId: conversationId, message: message, kind: kind),
                    )
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    for try await sse in sseStream(for: request, session: session) {
                        do {
                            guard let event = try ChatStreamEvent(sseEvent: sse) else { continue }
                            continuation.yield(event)
                        } catch {
                            throw APIClientError.decoding(underlying: String(describing: error))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // Conversations
    public func conversations() async throws -> ConversationListResponse {
        try await get(ConversationListResponse.self, "/ai/conversations")
    }

    public func conversation(id: String) async throws -> ConversationDetailResponse {
        try await get(ConversationDetailResponse.self, "/ai/conversations/\(id)")
    }

    public func deleteConversation(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/ai/conversations/\(id)")
    }

    // Action cards
    public func confirmAction(id: String) async throws -> ActionResponse {
        try await post(ActionResponse.self, "/ai/actions/\(id)/confirm")
    }

    public func rejectAction(id: String) async throws -> ActionResponse {
        try await post(ActionResponse.self, "/ai/actions/\(id)/reject")
    }

    // Briefings
    public func briefingToday() async throws -> BriefingDTO {
        try await get(BriefingDTO.self, "/ai/briefing/today")
    }

    public func wrapupToday() async throws -> BriefingDTO {
        try await get(BriefingDTO.self, "/ai/wrapup/today")
    }

    // Reviews
    public func startWeeklyReview(weekNumber: Int? = nil) async throws -> ReviewStartResponse {
        try await post(
            ReviewStartResponse.self,
            "/ai/reviews/weekly/start",
            body: WeeklyReviewStartRequest(weekNumber: weekNumber),
        )
    }

    public func startBlockReview() async throws -> ReviewStartResponse {
        try await post(ReviewStartResponse.self, "/ai/reviews/block/start")
    }

    public func closeReview(conversationId: String) async throws -> ReviewCloseResponse {
        try await post(ReviewCloseResponse.self, "/ai/reviews/\(conversationId)/close")
    }
}
