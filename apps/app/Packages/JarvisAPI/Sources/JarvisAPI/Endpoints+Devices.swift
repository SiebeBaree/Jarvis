import Foundation

/// Which APNs environment issued a token. A Debug build gets a sandbox token
/// even though it talks to the production API, so the server cannot infer this.
public enum DeviceEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

public struct DeviceRegisterRequest: Encodable, Sendable {
    public let deviceToken: String
    public let platform: String
    public let environment: DeviceEnvironment

    public init(deviceToken: String, environment: DeviceEnvironment) {
        self.deviceToken = deviceToken
        self.platform = "ios"
        self.environment = environment
    }
}

public struct DeviceRevokeRequest: Encodable, Sendable {
    public let deviceToken: String

    public init(deviceToken: String) {
        self.deviceToken = deviceToken
    }
}

public struct DeviceDTO: Codable, Sendable, Identifiable {
    public let id: String
    public let deviceToken: String
    public let platform: String
    public let environment: DeviceEnvironment
}

extension APIClient {
    /// Register this device for push. Safe to call on every launch: the server
    /// keys on the token, so this refreshes the row instead of adding one.
    @discardableResult
    public func registerDevice(
        token: String,
        environment: DeviceEnvironment,
    ) async throws -> DeviceDTO {
        try await post(
            DeviceDTO.self,
            "/devices",
            body: DeviceRegisterRequest(deviceToken: token, environment: environment),
        )
    }

    /// Stop sending to this device. Called on sign-out, while the session token
    /// is still valid.
    @discardableResult
    public func revokeDevice(token: String) async throws -> OkResponse {
        try await post(
            OkResponse.self,
            "/devices/revoke",
            body: DeviceRevokeRequest(deviceToken: token),
        )
    }
}
