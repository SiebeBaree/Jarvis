import Foundation

// Minimal server-sent-events (text/event-stream) client used by the chat
// endpoint. Only the subset of the SSE spec the server emits is supported:
// `event:` / `data:` fields, comments (lines starting with ":"), multi-line
// data joined with "\n", dispatch on blank line.

public struct SSEEvent: Sendable, Equatable {
    public let event: String
    public let data: String

    public init(event: String, data: String) {
        self.event = event
        self.data = data
    }
}

/// Pure line-level SSE parser, separated from the transport for testability.
/// Feed it text chunks (any split points, including mid-line); it returns the
/// events completed by that chunk.
public struct SSELineParser: Sendable {
    private var pending = ""
    private var eventName = ""
    private var dataLines: [String] = []

    public init() {}

    /// Feeds a chunk of stream text and returns any events it completed.
    public mutating func feed(_ chunk: String) -> [SSEEvent] {
        pending += chunk
        var events: [SSEEvent] = []
        // "\r\n" is a single Character (grapheme cluster) in Swift, so match
        // it alongside "\n". A chunk ending in "\r" stays pending and merges
        // with a leading "\n" from the next chunk.
        while let newline = pending.firstIndex(where: { $0 == "\n" || $0 == "\r\n" }) {
            let line = String(pending[..<newline])
            pending = String(pending[pending.index(after: newline)...])
            if let event = feed(line: line) { events.append(event) }
        }
        return events
    }

    /// Feeds a single line (without its terminator). Returns an event when the
    /// line is the blank dispatch line ending a non-empty event.
    public mutating func feed(line: String) -> SSEEvent? {
        if line.isEmpty {
            defer {
                eventName = ""
                dataLines = []
            }
            guard !dataLines.isEmpty else { return nil }
            return SSEEvent(
                event: eventName.isEmpty ? "message" : eventName,
                data: dataLines.joined(separator: "\n"),
            )
        }
        if line.hasPrefix(":") { return nil } // comment

        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = line[...]
            value = ""
        }

        switch field {
        case "event": eventName = String(value)
        case "data": dataLines.append(String(value))
        default: break // id, retry, unknown fields — ignored
        }
        return nil
    }
}

private struct SSEErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
    }
    let error: Payload
}

/// Opens `request` on `session` and yields parsed SSE events. An HTTP status
/// >= 400 before any event is delivered surfaces as a thrown APIClientError.
/// Cancelling the consuming task stops the underlying byte stream.
func sseStream(for request: URLRequest, session: URLSession) -> AsyncThrowingStream<SSEEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                let (bytes, response) = try await session.bytes(for: request)

                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 { throw APIClientError.unauthorized }
                guard (200..<300).contains(status) else {
                    var body = Data()
                    for try await byte in bytes {
                        body.append(byte)
                        if body.count > 64 * 1024 { break }
                    }
                    if let envelope = try? JSONDecoder().decode(SSEErrorEnvelope.self, from: body) {
                        throw APIClientError.api(
                            code: envelope.error.code,
                            message: envelope.error.message,
                            status: status,
                        )
                    }
                    throw APIClientError.api(
                        code: "http_\(status)",
                        message: "Request failed (\(status))",
                        status: status,
                    )
                }

                // Assemble lines at the byte level ("\n" is never part of a
                // multi-byte UTF-8 scalar, so this is split-safe), then hand
                // complete lines to the parser.
                var parser = SSELineParser()
                var lineBytes: [UInt8] = []
                for try await byte in bytes {
                    guard byte == UInt8(ascii: "\n") else {
                        lineBytes.append(byte)
                        continue
                    }
                    if lineBytes.last == UInt8(ascii: "\r") { lineBytes.removeLast() }
                    let line = String(decoding: lineBytes, as: UTF8.self)
                    lineBytes = []
                    if let event = parser.feed(line: line) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch let error as APIClientError {
                continuation.finish(throwing: error)
            } catch let error as URLError where error.code == .cancelled {
                continuation.finish()
            } catch {
                continuation.finish(throwing: APIClientError.network(underlying: error.localizedDescription))
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
