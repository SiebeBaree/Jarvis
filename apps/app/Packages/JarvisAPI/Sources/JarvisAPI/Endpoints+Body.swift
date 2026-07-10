import Foundation

// Stage 3+4 endpoints: metric types & entries, weekly scores, progress photos.

public struct MetricTypeCreateRequest: Encodable, Sendable {
    public var name: String
    public var unit: String
    public var decimals: Int?
    public var goalValue: Double?
    public var goalDirection: String?

    public init(
        name: String,
        unit: String,
        decimals: Int? = nil,
        goalValue: Double? = nil,
        goalDirection: String? = nil,
    ) {
        self.name = name
        self.unit = unit
        self.decimals = decimals
        self.goalValue = goalValue
        self.goalDirection = goalDirection
    }
}

private struct MetricValueBody: Encodable, Sendable {
    let value: Double
}

extension APIClient {
    // Metric types
    public func metricTypes() async throws -> MetricTypeListResponse {
        try await get(MetricTypeListResponse.self, "/metric-types")
    }

    public func createMetricType(_ request: MetricTypeCreateRequest) async throws -> MetricTypeDTO {
        try await post(MetricTypeDTO.self, "/metric-types", body: request)
    }

    public func patchMetricType(id: String, _ patch: JSONObject) async throws -> MetricTypeDTO {
        try await self.patch(MetricTypeDTO.self, "/metric-types/\(id)", body: patch)
    }

    public func deleteMetricType(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/metric-types/\(id)")
    }

    // Metric entries
    public func metricEntries(
        typeId: String? = nil,
        from: DayKey? = nil,
        to: DayKey? = nil,
    ) async throws -> MetricEntryListResponse {
        var query: [URLQueryItem] = []
        if let typeId { query.append(URLQueryItem(name: "typeId", value: typeId)) }
        if let from { query.append(URLQueryItem(name: "from", value: from)) }
        if let to { query.append(URLQueryItem(name: "to", value: to)) }
        return try await get(MetricEntryListResponse.self, "/metrics", query: query)
    }

    public func putMetric(typeId: String, dayKey: DayKey, value: Double) async throws -> MetricEntryDTO {
        try await put(MetricEntryDTO.self, "/metrics/\(typeId)/\(dayKey)", body: MetricValueBody(value: value))
    }

    public func deleteMetric(typeId: String, dayKey: DayKey) async throws -> OkResponse {
        try await delete(OkResponse.self, "/metrics/\(typeId)/\(dayKey)")
    }

    // Weekly scores
    public func weeklyScores(blockId: String) async throws -> WeeklyScoresResponse {
        try await get(
            WeeklyScoresResponse.self,
            "/scores/weekly",
            query: [URLQueryItem(name: "blockId", value: blockId)],
        )
    }

    // Photos
    public func photos(from: DayKey, to: DayKey) async throws -> PhotoListResponse {
        try await get(
            PhotoListResponse.self,
            "/photos",
            query: [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)],
        )
    }

    public func uploadPhoto(
        data: Data,
        contentType: String,
        angle: String,
        dayKey: DayKey,
    ) async throws -> PhotoDTO {
        try await upload(
            PhotoDTO.self,
            "/photos",
            query: [URLQueryItem(name: "angle", value: angle), URLQueryItem(name: "dayKey", value: dayKey)],
            data: data,
            contentType: contentType,
        )
    }

    public func deletePhoto(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/photos/\(id)")
    }
}
