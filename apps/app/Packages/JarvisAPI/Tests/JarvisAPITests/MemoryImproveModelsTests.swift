import Foundation
import Testing
@testable import JarvisAPI

@Suite struct MemoryImproveModelsTests {
    private let decoder = JSONDecoder()

    @Test func decodesMemoryList() throws {
        let json = """
        {"memories":[{"id":"m1","category":"work","content":"He is the technical co-founder of Enkryptify.","source":"seeding","createdAt":"2026-07-12T10:00:00.000Z","updatedAt":"2026-07-12T10:00:00.000Z"}]}
        """
        let response = try decoder.decode(MemoryListResponse.self, from: Data(json.utf8))
        #expect(response.memories.count == 1)
        #expect(response.memories[0].category == "work")
        #expect(response.memories[0].source == "seeding")
    }

    @Test func decodesImprovementAreaListWithDueState() throws {
        let json = """
        {"areas":[
          {"id":"a1","name":"Posture","emoji":"🧍","betterLooksLike":"Straight back","sortOrder":0,
           "archived":false,"dueThisWeek":false,
           "thisWeek":{"id":"c1","dayKey":"2026-07-08","hasCommentary":true},"lastCheckinAt":"2026-07-08"},
          {"id":"a2","name":"Clothing","emoji":null,"betterLooksLike":null,"sortOrder":1,
           "archived":false,"dueThisWeek":true,"thisWeek":null,"lastCheckinAt":null}
        ],"anyDueThisWeek":true,"currentWeekKey":"2026-07-06"}
        """
        let response = try decoder.decode(ImprovementAreaListResponse.self, from: Data(json.utf8))
        #expect(response.anyDueThisWeek)
        #expect(response.areas[0].thisWeek?.hasCommentary == true)
        #expect(response.areas[1].dueThisWeek)
        #expect(response.areas[1].thisWeek == nil)
    }

    @Test func decodesCheckinTimelineWithPendingCommentary() throws {
        let json = """
        {"checkins":[{"id":"c1","areaId":"a1","weekKey":"2026-07-06","dayKey":"2026-07-08",
          "url":"https://blob.example/x.jpg","aiCommentary":null,"aiGeneratedAt":null,
          "createdAt":"2026-07-08T09:00:00.000Z"}]}
        """
        let response = try decoder.decode(AreaCheckinListResponse.self, from: Data(json.utf8))
        #expect(response.checkins[0].aiCommentary == nil)
        #expect(response.checkins[0].weekKey == "2026-07-06")
    }

    @Test func memoryCategoriesCoverServerSet() {
        let expected = ["identity", "work", "health", "appearance", "preferences", "relationships", "context"]
        #expect(MemoryCategory.allCases.map(\.rawValue) == expected)
    }
}
