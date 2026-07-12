import Foundation

// Improvement-area endpoints: CRUD + weekly photo check-ins.

public struct ImprovementAreaCreateRequest: Encodable, Sendable {
    public var name: String
    public var emoji: String?
    public var betterLooksLike: String?
    public var sortOrder: Int?

    public init(name: String, emoji: String? = nil, betterLooksLike: String? = nil, sortOrder: Int? = nil) {
        self.name = name
        self.emoji = emoji
        self.betterLooksLike = betterLooksLike
        self.sortOrder = sortOrder
    }
}

extension APIClient {
    public func improvementAreas(includeArchived: Bool = false) async throws -> ImprovementAreaListResponse {
        try await get(
            ImprovementAreaListResponse.self,
            "/improvement-areas",
            query: includeArchived ? [URLQueryItem(name: "includeArchived", value: "true")] : [],
        )
    }

    public func createImprovementArea(_ request: ImprovementAreaCreateRequest) async throws -> ImprovementAreaDTO {
        try await post(ImprovementAreaDTO.self, "/improvement-areas", body: request)
    }

    public func patchImprovementArea(id: String, _ patch: JSONObject) async throws -> ImprovementAreaDTO {
        try await self.patch(ImprovementAreaDTO.self, "/improvement-areas/\(id)", body: patch)
    }

    public func deleteImprovementArea(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/improvement-areas/\(id)")
    }

    public func areaCheckins(areaId: String) async throws -> AreaCheckinListResponse {
        try await get(AreaCheckinListResponse.self, "/improvement-areas/\(areaId)/checkins")
    }

    public func uploadCheckin(
        areaId: String,
        dayKey: DayKey,
        data: Data,
        contentType: String,
    ) async throws -> AreaCheckinDTO {
        try await upload(
            AreaCheckinDTO.self,
            "/improvement-areas/\(areaId)/checkins",
            query: [URLQueryItem(name: "dayKey", value: dayKey)],
            data: data,
            contentType: contentType,
        )
    }
}
