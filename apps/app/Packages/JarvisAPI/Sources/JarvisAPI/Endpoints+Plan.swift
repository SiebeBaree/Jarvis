import Foundation

// Stage 2 endpoints: vision, blocks, tactics.

private struct VisionPutRequest: Encodable, Sendable {
    let content: String
}

private struct BlockCreateRequest: Encodable, Sendable {
    let title: String
    let startDate: DayKey
}

private struct TacticCreateRequest: Encodable, Sendable {
    let goalId: String
    let title: String
    let fromWeek: Int
    let toWeek: Int
}

private struct TacticWeekRequest: Encodable, Sendable {
    let done: Bool
}

extension APIClient {
    // Vision
    public func vision() async throws -> VisionDTO {
        try await get(VisionDTO.self, "/vision")
    }

    public func putVision(content: String) async throws -> VisionDTO {
        try await put(VisionDTO.self, "/vision", body: VisionPutRequest(content: content))
    }

    // Blocks
    public func blocks() async throws -> BlockListResponse {
        try await get(BlockListResponse.self, "/blocks")
    }

    public func createBlock(title: String, startDate: DayKey) async throws -> BlockDTO {
        try await post(BlockDTO.self, "/blocks", body: BlockCreateRequest(title: title, startDate: startDate))
    }

    public func activateBlock(id: String) async throws -> BlockDTO {
        try await post(BlockDTO.self, "/blocks/\(id)/activate")
    }

    public func deleteBlock(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/blocks/\(id)")
    }

    public func currentBlock() async throws -> CurrentBlockResponse {
        try await get(CurrentBlockResponse.self, "/blocks/current")
    }

    // Tactics
    public func tactics(goalId: String? = nil, blockId: String? = nil) async throws -> TacticListResponse {
        var query: [URLQueryItem] = []
        if let goalId { query.append(URLQueryItem(name: "goalId", value: goalId)) }
        if let blockId { query.append(URLQueryItem(name: "blockId", value: blockId)) }
        return try await get(TacticListResponse.self, "/tactics", query: query)
    }

    public func createTactic(goalId: String, title: String, fromWeek: Int = 1, toWeek: Int = 12) async throws -> TacticDTO {
        try await post(
            TacticDTO.self,
            "/tactics",
            body: TacticCreateRequest(goalId: goalId, title: title, fromWeek: fromWeek, toWeek: toWeek),
        )
    }

    public func patchTactic(id: String, _ patch: JSONObject) async throws -> TacticDTO {
        try await self.patch(TacticDTO.self, "/tactics/\(id)", body: patch)
    }

    public func deleteTactic(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/tactics/\(id)")
    }

    public func setTacticWeek(id: String, weekNumber: Int, done: Bool) async throws -> TacticWeekResponse {
        try await put(
            TacticWeekResponse.self,
            "/tactics/\(id)/weeks/\(weekNumber)",
            body: TacticWeekRequest(done: done),
        )
    }
}
