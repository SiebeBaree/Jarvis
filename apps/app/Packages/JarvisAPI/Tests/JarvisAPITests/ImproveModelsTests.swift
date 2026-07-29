import Foundation
import Testing
@testable import JarvisAPI

@Suite struct ImproveModelsTests {
    private let decoder = JSONDecoder()

    @Test func decodesImprovementAreaListWithDueState() throws {
        let json = """
        {"areas":[
          {"id":"a1","name":"Posture","emoji":"🧍","betterLooksLike":"Straight back","sortOrder":0,
           "archived":false,"dueThisWeek":false,
           "thisWeek":{"id":"c1","dayKey":"2026-07-08"},"lastCheckinAt":"2026-07-08"},
          {"id":"a2","name":"Clothing","emoji":null,"betterLooksLike":null,"sortOrder":1,
           "archived":false,"dueThisWeek":true,"thisWeek":null,"lastCheckinAt":null}
        ],"anyDueThisWeek":true,"currentWeekKey":"2026-07-06"}
        """
        let response = try decoder.decode(ImprovementAreaListResponse.self, from: Data(json.utf8))
        #expect(response.anyDueThisWeek)
        #expect(response.areas[0].thisWeek?.dayKey == "2026-07-08")
        #expect(response.areas[1].dueThisWeek)
        #expect(response.areas[1].thisWeek == nil)
    }

    @Test func decodesCheckinTimeline() throws {
        let json = """
        {"checkins":[{"id":"c1","areaId":"a1","weekKey":"2026-07-06","dayKey":"2026-07-08",
          "url":"https://blob.example/x.jpg","createdAt":"2026-07-08T09:00:00.000Z"}]}
        """
        let response = try decoder.decode(AreaCheckinListResponse.self, from: Data(json.utf8))
        #expect(response.checkins[0].weekKey == "2026-07-06")
        #expect(response.checkins[0].url.hasSuffix("x.jpg"))
    }
}
