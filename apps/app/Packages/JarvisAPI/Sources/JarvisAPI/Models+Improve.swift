import Foundation

// Improvement areas (posture, clothing, teeth...) with weekly photo check-ins.

public struct ThisWeekCheckinDTO: Codable, Sendable, Equatable {
    public let id: String
    public let dayKey: DayKey
}

public struct ImprovementAreaDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let emoji: String?
    public let betterLooksLike: String?
    public let sortOrder: Int
    public let archived: Bool
    public let dueThisWeek: Bool
    public let thisWeek: ThisWeekCheckinDTO?
    public let lastCheckinAt: DayKey?
}

public struct ImprovementAreaListResponse: Codable, Sendable {
    public let areas: [ImprovementAreaDTO]
    public let anyDueThisWeek: Bool
    public let currentWeekKey: DayKey
}

public struct AreaCheckinDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let areaId: String
    public let weekKey: DayKey
    public let dayKey: DayKey
    public let url: String
    public let createdAt: String
}

public struct AreaCheckinListResponse: Codable, Sendable {
    public let checkins: [AreaCheckinDTO]
}
