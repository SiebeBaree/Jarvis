import Foundation
import Testing
@testable import JarvisAPI

@Suite struct GoalModelsTests {
    private let decoder = JSONDecoder()

    @Test func decodesNumericGoalWithMilestones() throws {
        let json = """
        {"goals":[{
          "id":"g1","areaId":null,"title":"Reach 10k MRR","description":null,
          "horizon":"long","status":"active",
          "startDate":"2026-01-01","targetDate":"2026-12-31",
          "unit":"EUR","startValue":0,"targetValue":10000,"currentValue":3400,
          "sortOrder":0,"completedAt":null,
          "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-06-01T00:00:00.000Z",
          "milestones":[{"id":"m1","goalId":"g1","title":"First 10 customers",
                         "doneAt":"2026-03-01T00:00:00.000Z","sortOrder":0}],
          "tracking":"numeric","progress":0.34,"timeProgress":0.41,
          "daysTotal":365,"daysRemaining":213,"milestonesDone":1,"milestonesTotal":1
        }]}
        """
        let response = try decoder.decode(GoalListResponse.self, from: Data(json.utf8))
        let goal = try #require(response.goals.first)
        #expect(goal.horizon == .long)
        #expect(goal.tracking == .numeric)
        #expect(goal.progress == 0.34)
        #expect(goal.milestones.first?.isDone == true)
    }

    @Test func decodesUntrackedGoal() throws {
        let json = """
        {"goals":[{
          "id":"g2","areaId":null,"title":"Read more","description":null,
          "horizon":"short","status":"active",
          "startDate":"2026-07-01","targetDate":"2026-09-30",
          "unit":null,"startValue":null,"targetValue":null,"currentValue":null,
          "sortOrder":0,"completedAt":null,
          "createdAt":"2026-07-01T00:00:00.000Z","updatedAt":"2026-07-01T00:00:00.000Z",
          "milestones":[],
          "tracking":"none","progress":null,"timeProgress":0.3,
          "daysTotal":92,"daysRemaining":64,"milestonesDone":0,"milestonesTotal":0
        }]}
        """
        let goal = try #require(decoder.decode(GoalListResponse.self, from: Data(json.utf8)).goals.first)
        #expect(goal.tracking == .none)
        #expect(goal.progress == nil)
        #expect(goal.timeProgress == 0.3)
    }
}
