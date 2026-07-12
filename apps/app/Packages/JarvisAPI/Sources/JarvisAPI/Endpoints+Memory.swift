import Foundation

// AI memory endpoints + account reset.

public struct MemoryCreateRequest: Encodable, Sendable {
    public let category: String
    public let content: String
    public init(category: String, content: String) {
        self.category = category
        self.content = content
    }
}

private struct AccountResetRequest: Encodable, Sendable {
    let confirm: String
}

extension APIClient {
    // Memories
    public func memories() async throws -> MemoryListResponse {
        try await get(MemoryListResponse.self, "/memories")
    }

    public func createMemory(category: String, content: String) async throws -> MemoryDTO {
        try await post(MemoryDTO.self, "/memories", body: MemoryCreateRequest(category: category, content: content))
    }

    public func patchMemory(id: String, _ patch: JSONObject) async throws -> MemoryDTO {
        try await self.patch(MemoryDTO.self, "/memories/\(id)", body: patch)
    }

    public func deleteMemory(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/memories/\(id)")
    }

    // Account
    /// Wipes every domain row for the account (keeps login + settings).
    public func resetAccount() async throws -> OkResponse {
        try await post(OkResponse.self, "/account/reset", body: AccountResetRequest(confirm: "RESET"))
    }
}
