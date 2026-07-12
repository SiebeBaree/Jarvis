import Foundation

// Stage 2 DTOs: vision, blocks, tactics.

// MARK: - Vision

public struct VisionDTO: Codable, Sendable, Equatable {
    public let content: String
    public let updatedAt: String
}

// MARK: - Blocks

public struct BlockDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let number: Int
    public let title: String
    public let startDate: DayKey
    public let endDate: DayKey
    public let status: String // planned | active | completed
}

public struct BlockListResponse: Codable, Sendable {
    public let blocks: [BlockDTO]
}

public struct WeekScoreDTO: Codable, Sendable, Identifiable, Equatable {
    public var id: Int { weekNumber }
    public let weekNumber: Int
    public let avg: Double?
}

public struct TacticDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let goalId: String
    public let title: String
    public let fromWeek: Int
    public let toWeek: Int
    public let sortOrder: Int
    public let completedWeeks: [Int]
}

public struct TacticListResponse: Codable, Sendable {
    public let tactics: [TacticDTO]
}

public struct TacticWeekResponse: Codable, Sendable {
    public let tacticId: String
    public let weekNumber: Int
    public let done: Bool
    public let completedWeeks: [Int]
}

public struct GoalWithProgressDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let blockId: String?
    public let areaId: String?
    public let title: String
    public let description: String?
    public let status: String
    public let trackStatus: String? // on_track | at_risk | done
    public let manualProgress: Int?
    public let sortOrder: Int
    public let areaName: String?
    public let areaEmoji: String?
    public let progress: Double? // 0...1 or null (no tactics yet)
    public let tactics: [TacticDTO]
}

public struct CurrentBlockResponse: Codable, Sendable {
    public let block: BlockDTO?
    public let isUpcoming: Bool
    public let weekNumber: Int?
    public let isReviewWeek: Bool
    public let weekScores: [WeekScoreDTO]
    public let goals: [GoalWithProgressDTO]
}
