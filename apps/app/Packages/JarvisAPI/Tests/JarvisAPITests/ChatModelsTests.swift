import Foundation
import Testing
@testable import JarvisAPI

struct ChatModelsTests {
    @Test func decodesConversationDetail() throws {
        let json = """
        {
          "conversation": {
            "id": "conv_1",
            "kind": "weekly_review",
            "title": "Week 3 review",
            "blockId": "blk_1",
            "weekNumber": 3,
            "outcome": {
              "wins": ["Shipped the API"],
              "struggles": ["Sleep"],
              "adjustments": ["Earlier bedtime"],
              "focusNextWeek": "Ship the app"
            },
            "createdAt": "2026-07-10T08:00:00.000Z",
            "updatedAt": "2026-07-10T09:00:00.000Z"
          },
          "messages": [
            {
              "id": "msg_1",
              "role": "user",
              "parts": [{ "type": "text", "text": "How did my week go?" }],
              "createdAt": "2026-07-10T08:00:00.000Z"
            },
            {
              "id": "msg_2",
              "role": "assistant",
              "parts": [
                { "type": "text", "text": "Let me check." },
                { "type": "tool_call", "callId": "call_1", "name": "get_scores", "args": { "from": "2026-07-06" } }
              ],
              "createdAt": "2026-07-10T08:00:05.000Z"
            },
            {
              "id": "msg_3",
              "role": "tool",
              "parts": [
                { "type": "tool_result", "callId": "call_1", "result": [1, 2, 3] },
                { "type": "shiny_new_thing", "payload": { "nested": true } }
              ],
              "createdAt": "2026-07-10T08:00:06.000Z"
            }
          ],
          "actions": [
            {
              "id": "act_1",
              "conversationId": "conv_1",
              "messageId": "msg_2",
              "toolName": "create_task",
              "summary": "Create task \\"Ship the app\\"",
              "status": "proposed",
              "args": { "title": "Ship the app" },
              "result": null,
              "createdAt": "2026-07-10T08:00:07.000Z",
              "resolvedAt": null
            }
          ]
        }
        """
        let detail = try JSONDecoder().decode(ConversationDetailResponse.self, from: Data(json.utf8))

        #expect(detail.conversation.kind == "weekly_review")
        #expect(detail.conversation.outcome?.wins == ["Shipped the API"])
        #expect(detail.conversation.outcome?.focusNextWeek == "Ship the app")

        #expect(detail.messages.count == 3)
        #expect(detail.messages[0].parts == [.text("How did my week go?")])
        #expect(detail.messages[1].parts == [
            .text("Let me check."),
            .toolCall(callId: "call_1", name: "get_scores"),
        ])
        #expect(detail.messages[2].parts == [
            .toolResult(callId: "call_1"),
            .unknown(type: "shiny_new_thing"),
        ])

        #expect(detail.actions.count == 1)
        #expect(detail.actions[0].toolName == "create_task")
        #expect(detail.actions[0].status == "proposed")
        #expect(detail.actions[0].resolvedAt == nil)
    }

    @Test func decodesConversationWithoutOutcome() throws {
        let json = """
        {
          "id": "conv_2",
          "kind": "chat",
          "title": null,
          "blockId": null,
          "weekNumber": null,
          "createdAt": "2026-07-10T08:00:00.000Z",
          "updatedAt": "2026-07-10T08:00:00.000Z"
        }
        """
        let conversation = try JSONDecoder().decode(ConversationDTO.self, from: Data(json.utf8))
        #expect(conversation.outcome == nil)
        #expect(conversation.title == nil)
    }

    @Test func parsesMetaEvent() throws {
        let event = try ChatStreamEvent(sseEvent: SSEEvent(event: "meta", data: #"{"conversationId":"conv_1"}"#))
        #expect(event == .meta(conversationId: "conv_1"))
    }

    @Test func parsesDeltaEvent() throws {
        let event = try ChatStreamEvent(sseEvent: SSEEvent(event: "message_delta", data: #"{"text":"Hel"}"#))
        #expect(event == .delta("Hel"))
    }

    @Test func parsesToolCallEvent() throws {
        let event = try ChatStreamEvent(
            sseEvent: SSEEvent(event: "tool_call", data: #"{"name":"get_scores","status":"running"}"#),
        )
        #expect(event == .toolCall(name: "get_scores", status: "running"))
    }

    @Test func parsesActionEvent() throws {
        let data = """
        {
          "id": "act_1",
          "conversationId": "conv_1",
          "messageId": "msg_1",
          "toolName": "create_task",
          "summary": "Create a task",
          "status": "proposed",
          "createdAt": "2026-07-10T08:00:00.000Z",
          "resolvedAt": null
        }
        """
        let event = try ChatStreamEvent(sseEvent: SSEEvent(event: "action", data: data))
        guard case .action(let action)? = event else {
            Issue.record("expected .action, got \(String(describing: event))")
            return
        }
        #expect(action.id == "act_1")
        #expect(action.status == "proposed")
    }

    @Test func parsesDoneEvent() throws {
        let event = try ChatStreamEvent(
            sseEvent: SSEEvent(event: "message_done", data: #"{"messageId":"msg_1","conversationId":"conv_1"}"#),
        )
        #expect(event == .done(messageId: "msg_1", conversationId: "conv_1"))
    }

    @Test func parsesErrorEvent() throws {
        let event = try ChatStreamEvent(
            sseEvent: SSEEvent(event: "error", data: #"{"code":"rate_limited","message":"Slow down"}"#),
        )
        #expect(event == .error(code: "rate_limited", message: "Slow down"))
    }

    @Test func unknownEventNameIsNil() throws {
        let event = try ChatStreamEvent(sseEvent: SSEEvent(event: "heartbeat", data: "{}"))
        #expect(event == nil)
    }

    @Test func malformedKnownEventThrows() {
        #expect(throws: (any Error).self) {
            try ChatStreamEvent(sseEvent: SSEEvent(event: "meta", data: "not json"))
        }
    }

    @Test func dayPayloadDecodesWithoutPausedTaskCount() throws {
        // Regression guard: older server payloads omit pausedTaskCount.
        let json = """
        {
          "dayKey": "2026-07-10",
          "weekNumber": null,
          "isReviewWeek": false,
          "block": null,
          "score": {
            "dayKey": "2026-07-10",
            "total": null,
            "taskPoints": null,
            "habitPoints": null,
            "feelPoints": null,
            "applicableWeight": 100,
            "isReviewWeek": false,
            "isFinal": false,
            "breakdown": { "tasks": [], "habits": [] }
          },
          "tasksDue": [],
          "overdueTasks": [],
          "habits": [],
          "mood": null,
          "yesterdayMoodMissing": false
        }
        """
        let payload = try JSONDecoder().decode(DayPayload.self, from: Data(json.utf8))
        #expect(payload.pausedTaskCount == nil)
    }

    @Test func dayPayloadDecodesPausedTaskCount() throws {
        let json = """
        {
          "dayKey": "2026-07-10",
          "weekNumber": null,
          "isReviewWeek": false,
          "block": null,
          "score": {
            "dayKey": "2026-07-10",
            "total": null,
            "taskPoints": null,
            "habitPoints": null,
            "feelPoints": null,
            "applicableWeight": 100,
            "isReviewWeek": false,
            "isFinal": false,
            "breakdown": { "tasks": [], "habits": [] }
          },
          "tasksDue": [],
          "overdueTasks": [],
          "habits": [],
          "mood": null,
          "yesterdayMoodMissing": false,
          "pausedTaskCount": 2
        }
        """
        let payload = try JSONDecoder().decode(DayPayload.self, from: Data(json.utf8))
        #expect(payload.pausedTaskCount == 2)
    }
}
