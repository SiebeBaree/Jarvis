import Foundation

public enum APIClientError: Error, LocalizedError, Sendable {
    /// 401 — the app should clear the stored token and return to login.
    case unauthorized
    case api(code: String, message: String, status: Int)
    case network(underlying: String)
    case decoding(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Session expired — please sign in again."
        case .api(_, let message, _): message
        case .network: "Could not reach the server. Check your connection."
        case .decoding: "Unexpected response from the server."
        }
    }
}

/// Loose JSON value for PATCH bodies where explicit `null` (clear the field)
/// must be distinguishable from an absent key.
public enum JSONValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

public typealias JSONObject = [String: JSONValue]

struct EmptyBody: Encodable, Sendable {}

public actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private var token: String?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            // Interview rounds run on a high-reasoning model and can take
            // well over URLSession's 60 s default.
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 240
            self.session = URLSession(configuration: configuration)
        }
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public func setToken(_ token: String?) {
        self.token = token
    }

    private struct ErrorEnvelope: Decodable {
        struct Payload: Decodable {
            let code: String
            let message: String
        }
        let error: Payload
    }

    /// Transient failures worth retrying: the connection never produced a
    /// usable answer. A cold Vercel lambda waking a suspended Neon compute is
    /// the common case — without this the first request of a session fails and
    /// the user has to tap Retry themselves.
    private static func isTransient(_ error: APIClientError) -> Bool {
        switch error {
        case .network: true
        case .api(_, _, let status): status >= 500 || status == 408 || status == 429
        case .unauthorized, .decoding: false
        }
    }

    /// Retries are only safe on reads — a replayed POST could double-create.
    private static func attemptCount(for method: String) -> Int {
        method == "GET" ? 3 : 1
    }

    func send<T: Decodable & Sendable>(
        _ type: T.Type,
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: (some Encodable & Sendable)? = nil as EmptyBody?,
    ) async throws -> T {
        let maxAttempts = Self.attemptCount(for: method)
        var attempt = 1
        while true {
            do {
                return try await perform(type, method: method, path: path, query: query, body: body)
            } catch let error as APIClientError where attempt < maxAttempts && Self.isTransient(error) {
                // 400 ms, then 1.2 s — long enough for a warm-up, short enough
                // that a genuinely dead server still fails quickly.
                try? await Task.sleep(for: .milliseconds(400 * attempt * attempt))
                attempt += 1
            }
        }
    }

    private func perform<T: Decodable & Sendable>(
        _ type: T.Type,
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: (some Encodable & Sendable)? = nil as EmptyBody?,
    ) async throws -> T {
        var components = URLComponents(
            url: baseURL.appending(path: "/api/v1" + path),
            resolvingAgainstBaseURL: false,
        )!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIClientError.network(underlying: error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw APIClientError.unauthorized }
        guard (200..<300).contains(status) else {
            if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
                throw APIClientError.api(
                    code: envelope.error.code,
                    message: envelope.error.message,
                    status: status,
                )
            }
            throw APIClientError.api(code: "http_\(status)", message: "Request failed (\(status))", status: status)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIClientError.decoding(underlying: String(describing: error))
        }
    }

    /// Builds an authorized request without sending it, plus the session to
    /// send it on. Used by extension files that own the transport themselves
    /// (SSE streaming in Endpoints+Chat).
    func makeRequest(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: (some Encodable & Sendable)? = nil as EmptyBody?,
    ) throws -> (URLRequest, URLSession) {
        var components = URLComponents(
            url: baseURL.appending(path: "/api/v1" + path),
            resolvingAgainstBaseURL: false,
        )!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        return (request, session)
    }

    /// Replays a already-encoded request and discards the response body.
    /// The offline mutation queue stores requests as (method, path, JSON) so
    /// it can persist and retry them; it owns its own retry policy, so this
    /// deliberately does not retry internally.
    public func sendStored(method: String, path: String, body: Data?) async throws {
        var (request, session) = try makeRequest(method: method, path: path, body: nil as EmptyBody?)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIClientError.network(underlying: error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw APIClientError.unauthorized }
        guard (200..<300).contains(status) else {
            if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
                throw APIClientError.api(
                    code: envelope.error.code,
                    message: envelope.error.message,
                    status: status,
                )
            }
            throw APIClientError.api(code: "http_\(status)", message: "Request failed (\(status))", status: status)
        }
    }

    /// Like send(), but with a raw (non-JSON) request body — photo uploads.
    func upload<T: Decodable & Sendable>(
        _ type: T.Type,
        _ path: String,
        query: [URLQueryItem] = [],
        data body: Data,
        contentType: String,
    ) async throws -> T {
        var (request, session) = try makeRequest(method: "POST", path: path, query: query, body: nil as EmptyBody?)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIClientError.network(underlying: error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw APIClientError.unauthorized }
        guard (200..<300).contains(status) else {
            if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
                throw APIClientError.api(
                    code: envelope.error.code,
                    message: envelope.error.message,
                    status: status,
                )
            }
            throw APIClientError.api(code: "http_\(status)", message: "Request failed (\(status))", status: status)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIClientError.decoding(underlying: String(describing: error))
        }
    }

    func get<T: Decodable & Sendable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(type, method: "GET", path: path, query: query, body: nil as EmptyBody?)
    }

    func post<T: Decodable & Sendable>(
        _ type: T.Type,
        _ path: String,
        body: (some Encodable & Sendable)? = nil as EmptyBody?,
    ) async throws -> T {
        try await send(type, method: "POST", path: path, body: body)
    }

    func patch<T: Decodable & Sendable>(
        _ type: T.Type,
        _ path: String,
        body: some Encodable & Sendable,
    ) async throws -> T {
        try await send(type, method: "PATCH", path: path, body: body)
    }

    func put<T: Decodable & Sendable>(
        _ type: T.Type,
        _ path: String,
        body: some Encodable & Sendable,
    ) async throws -> T {
        try await send(type, method: "PUT", path: path, body: body)
    }

    func delete<T: Decodable & Sendable>(
        _ type: T.Type,
        _ path: String,
        body: (some Encodable & Sendable)? = nil as EmptyBody?,
    ) async throws -> T {
        try await send(type, method: "DELETE", path: path, body: body)
    }
}
