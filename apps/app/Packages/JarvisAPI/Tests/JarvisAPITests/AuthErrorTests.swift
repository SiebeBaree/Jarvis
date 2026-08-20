import Foundation
import Testing
@testable import JarvisAPI

/// Serves one canned response to every request.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"],
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// `POST /auth/login` answers 401 for a wrong password, the same status a
/// rejected bearer token gets. The client used to collapse both into
/// `.unauthorized`, so the login screen announced an expired session for an
/// account that had never signed in. The two are told apart by the server's
/// error code now, and these tests hold that line.
///
/// Serialized: the stub's canned response is shared state.
@Suite(.serialized) struct AuthErrorTests {
    private func client(status: Int, json: String) -> APIClient {
        StubURLProtocol.status = status
        StubURLProtocol.body = Data(json.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(
            baseURL: URL(string: "https://api.example.com")!,
            session: URLSession(configuration: configuration),
        )
    }

    @Test func wrongPasswordKeepsTheServersOwnMessage() async throws {
        let api = client(
            status: 401,
            json: #"{"error":{"code":"invalid_credentials","message":"Email or password is incorrect"}}"#,
        )
        do {
            _ = try await api.login(email: "a@b.com", password: "wrong", deviceName: nil)
            Issue.record("a wrong password should not succeed")
        } catch let error as APIClientError {
            guard case .api(let code, _, let status) = error else {
                Issue.record("wrong password mapped to \(error) instead of .api")
                return
            }
            #expect(code == "invalid_credentials")
            #expect(status == 401)
            #expect(error.localizedDescription == "Email or password is incorrect")
        }
    }

    @Test func rejectedTokenStillSignsTheUserOut() async throws {
        let api = client(
            status: 401,
            json: #"{"error":{"code":"unauthorized","message":"Invalid or revoked token"}}"#,
        )
        do {
            _ = try await api.me()
            Issue.record("a revoked token should not succeed")
        } catch let error as APIClientError {
            guard case .unauthorized = error else {
                Issue.record("a rejected token mapped to \(error) instead of .unauthorized")
                return
            }
        }
    }

    /// A 401 the app cannot read is treated as a dead session, which is the
    /// safe reading: it clears the token instead of stranding the user.
    @Test func unreadable401FallsBackToSigningOut() async throws {
        let api = client(status: 401, json: "not json at all")
        do {
            _ = try await api.me()
            Issue.record("a 401 should not succeed")
        } catch let error as APIClientError {
            guard case .unauthorized = error else {
                Issue.record("an unreadable 401 mapped to \(error) instead of .unauthorized")
                return
            }
        }
    }

    /// Non-401 failures were already fine; this pins the shared helper that now
    /// handles all of them.
    @Test func otherFailuresCarryTheServerMessage() async throws {
        let api = client(
            status: 409,
            json: #"{"error":{"code":"account_exists","message":"An account already exists on this server. Sign in with it instead."}}"#,
        )
        do {
            _ = try await api.register(email: "a@b.com", password: "longenough")
            Issue.record("a duplicate account should not succeed")
        } catch let error as APIClientError {
            #expect(error.localizedDescription == "An account already exists on this server. Sign in with it instead.")
        }
    }
}
