import Foundation

// Stage 3+4 DTOs: metric tracking, weekly score aggregates, progress photos.

// MARK: - Metrics

public struct MetricTypeDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let unit: String
    public let decimals: Int
    public let goalValue: Double?
    public let goalDirection: String? // up | down
    public let sortOrder: Int
    public let archivedAt: String?
}

public struct MetricTypeListResponse: Codable, Sendable {
    public let metricTypes: [MetricTypeDTO]
}

public struct MetricEntryDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let metricTypeId: String
    public let dayKey: DayKey
    public let value: Double
}

public struct MetricEntryListResponse: Codable, Sendable {
    public let entries: [MetricEntryDTO]
}

// MARK: - Weekly scores

public struct WeeklyScoreDTO: Codable, Sendable, Identifiable, Equatable {
    public var id: Int { weekNumber }
    public let weekNumber: Int
    public let avg: Double?
    public let from: DayKey
    public let to: DayKey
}

public struct WeeklyScoresResponse: Codable, Sendable {
    public let weeks: [WeeklyScoreDTO]
}

// MARK: - Photos

public struct PhotoDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let dayKey: DayKey
    public let angle: String // front | side | back | ...
    public let url: String
    public let contentType: String
    public let sizeBytes: Int
    public let createdAt: String
}

public struct PhotoListResponse: Codable, Sendable {
    public let photos: [PhotoDTO]
}
