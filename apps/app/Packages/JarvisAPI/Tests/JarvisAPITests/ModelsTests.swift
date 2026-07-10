import Foundation
import Testing
@testable import JarvisAPI

struct ModelsTests {
    @Test func decodesDayPayload() throws {
        let json = """
        {
          "dayKey": "2026-07-10",
          "weekNumber": null,
          "isReviewWeek": false,
          "block": null,
          "score": {
            "dayKey": "2026-07-10",
            "total": 75.5,
            "taskPoints": 28.57,
            "habitPoints": 32,
            "feelPoints": null,
            "applicableWeight": 80,
            "isReviewWeek": false,
            "isFinal": false,
            "breakdown": {
              "tasks": [{ "taskId": "a", "credit": 0.5, "late": false }],
              "habits": [{ "habitId": "h", "credit": 1, "reps": 2, "expected": 2, "reconciled": false }]
            }
          },
          "tasksDue": [],
          "overdueTasks": [],
          "habits": [],
          "mood": null,
          "yesterdayMoodMissing": true
        }
        """
        let payload = try JSONDecoder().decode(DayPayload.self, from: Data(json.utf8))
        #expect(payload.score.total == 75.5)
        #expect(payload.score.feelPoints == nil)
        #expect(payload.yesterdayMoodMissing)
    }

    @Test func encodesExplicitNullInPatch() throws {
        let patch: JSONObject = ["dueDate": .null, "title": .string("Renamed")]
        let data = try JSONEncoder().encode(patch)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["dueDate"] is NSNull)
        #expect(object?["title"] as? String == "Renamed")
    }
}
