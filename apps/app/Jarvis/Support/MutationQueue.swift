import Foundation
import JarvisAPI
import Network
import Observation

/// One write waiting to reach the server, stored as a replayable request.
nonisolated struct PendingMutation: Codable, Identifiable, Sendable {
    let id: UUID
    let method: String
    let path: String
    /// Pre-encoded JSON body; nil for bodyless POSTs and DELETEs.
    let body: Data?
    /// What this write changes — used to invalidate caches once it lands.
    let entities: [Entity]
    /// Short human description for the "couldn't save" banner.
    let label: String
    var attempts: Int
    let createdAt: Date
}

/// The offline write path. Mutations are applied to local state immediately,
/// appended here, and flushed to the server in the background — so a tap is
/// never blocked on the network, and a write made in a tunnel or with the app
/// killed mid-flight still lands later.
///
/// Replay safety is the whole game, because a queued request may be sent more
/// than once (retry after a timeout that actually succeeded, or a relaunch
/// before the response arrived). Every queued write must therefore be
/// idempotent: creates carry a client-generated UUID that the server upserts
/// on, patches send absolute values rather than deltas, and a DELETE that
/// finds nothing is treated as already done.
///
/// Order is preserved: the queue drains strictly FIFO and stops at the first
/// transient failure, so a "create task X" can never be overtaken by the
/// "rename task X" that follows it.
@Observable
@MainActor
final class MutationQueue {
    private(set) var pending: [PendingMutation] = []
    /// Set when a write was rejected outright (a 4xx that retrying can't fix).
    var failure: String?

    var hasPending: Bool { !pending.isEmpty }
    /// True while the device has no usable route to the server.
    private(set) var isOffline = false

    private var api: APIClient?
    private var onLanded: ((Set<Entity>) -> Void)?
    private var isFlushing = false
    private var retry: Task<Void, Never>?
    private var monitor: NWPathMonitor?

    private static let maxAttempts = 8

    private static let fileURL: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let directory = base.appending(path: "Jarvis", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "outbox.json")
    }()

    /// `onLanded` fires with the entities of every mutation the server has
    /// accepted, so caches can be marked stale and screens revalidated.
    func configure(api: APIClient, onLanded: @escaping (Set<Entity>) -> Void) {
        guard self.api == nil else { return }
        self.api = api
        self.onLanded = onLanded
        load()
        startMonitoring()
        flush()
    }

    // MARK: - Enqueueing

    /// Queues a write. Returns immediately — callers apply their optimistic
    /// change first and never await this.
    func enqueue(
        method: String,
        path: String,
        body: (some Encodable & Sendable)? = nil as EmptyEncodable?,
        entities: Set<Entity>,
        label: String,
    ) {
        let encoded = body.flatMap { try? JSONEncoder().encode($0) }
        pending.append(
            PendingMutation(
                id: UUID(),
                method: method,
                path: path,
                body: encoded,
                entities: Array(entities),
                label: label,
                attempts: 0,
                createdAt: .now,
            ),
        )
        save()
        flush()
    }

    // MARK: - Flushing

    func flush() {
        guard !isFlushing, !pending.isEmpty, api != nil else { return }
        Task { await drain() }
    }

    private func drain() async {
        guard !isFlushing, let api else { return }
        isFlushing = true
        defer { isFlushing = false }

        var landed: Set<Entity> = []
        while let mutation = pending.first {
            do {
                try await api.sendStored(method: mutation.method, path: mutation.path, body: mutation.body)
                landed.formUnion(mutation.entities)
                remove(mutation.id)
                isOffline = false
            } catch let error as APIClientError {
                if Self.isAlreadyApplied(error, method: mutation.method) {
                    // A replayed delete whose target is already gone, etc. —
                    // the intent holds, so treat it as landed.
                    landed.formUnion(mutation.entities)
                    remove(mutation.id)
                    continue
                }
                if Self.isTransient(error) {
                    isOffline = Self.isNetworkFailure(error)
                    bumpAttempts(mutation.id)
                    // Give up eventually so a permanently poisoned write can't
                    // wedge the queue behind it forever.
                    if (pending.first?.attempts ?? 0) >= Self.maxAttempts {
                        failure = "Couldn't sync \(mutation.label). It will be retried next time you open the app."
                        break
                    }
                    scheduleRetry()
                    break
                }
                // A rejection retrying cannot fix (validation, conflict, gone).
                failure = "\(mutation.label) couldn't be saved: \(error.errorDescription ?? "unknown error")"
                remove(mutation.id)
            } catch {
                bumpAttempts(mutation.id)
                scheduleRetry()
                break
            }
        }

        if !landed.isEmpty { onLanded?(landed) }
    }

    /// 401 is deliberately absent: the session is gone, so the queue holds and
    /// AppModel routes to login rather than discarding the user's writes.
    private static func isTransient(_ error: APIClientError) -> Bool {
        switch error {
        case .network, .unauthorized: true
        case .api(_, _, let status): status >= 500 || status == 408 || status == 429
        case .decoding: false
        }
    }

    private static func isNetworkFailure(_ error: APIClientError) -> Bool {
        if case .network = error { return true }
        return false
    }

    /// A replay whose effect already exists — the desired end state is reached.
    private static func isAlreadyApplied(_ error: APIClientError, method: String) -> Bool {
        guard case .api(_, _, let status) = error else { return false }
        return status == 404 && (method == "DELETE" || method == "PATCH")
    }

    private func remove(_ id: UUID) {
        pending.removeAll { $0.id == id }
        save()
    }

    private func bumpAttempts(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].attempts += 1
        save()
    }

    private func scheduleRetry() {
        retry?.cancel()
        let attempts = pending.first?.attempts ?? 1
        // 2s, 4s, 8s … capped at a minute.
        let delay = min(pow(2.0, Double(attempts)), 60)
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Flush the moment the network comes back rather than waiting out the
    /// current backoff — this is what makes reconnecting feel instant.
    private func startMonitoring() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let offline = path.status != .satisfied
                self.isOffline = offline
                if !offline {
                    self.retry?.cancel()
                    self.flush()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "jarvis.network-monitor"))
        self.monitor = monitor
    }

    // MARK: - Persistence

    private func save() {
        guard let url = Self.fileURL else { return }
        guard let data = try? JSONEncoder().encode(pending) else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let url = Self.fileURL,
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([PendingMutation].self, from: data)
        else { return }
        pending = stored
    }

    /// Sign-out drops queued writes along with the cached data they belong to.
    func clear() {
        retry?.cancel()
        pending.removeAll()
        failure = nil
        save()
    }
}

/// Stand-in for "no body" so `enqueue` can keep a generic body parameter.
nonisolated struct EmptyEncodable: Encodable, Sendable {}
