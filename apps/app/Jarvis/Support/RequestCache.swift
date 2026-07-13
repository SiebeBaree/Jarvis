import Foundation

/// In-memory TTL cache for GET responses — the app's TanStack-Query.
/// Navigating back to a screen within the TTL renders instantly from cache
/// instead of refetching; any successful mutation clears the whole cache
/// (via AppModel.invalidateToday), so screens refetch fresh data next load.
@MainActor
final class RequestCache {
    static let defaultTTL: TimeInterval = 180 // 3 minutes

    private struct Entry {
        let value: Any
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]

    /// Returns the cached value when present and younger than `ttl`.
    func get<T>(_ key: String, ttl: TimeInterval = RequestCache.defaultTTL) -> T? {
        guard let entry = entries[key],
              Date.now.timeIntervalSince(entry.storedAt) < ttl else {
            entries[key] = nil
            return nil
        }
        return entry.value as? T
    }

    func set(_ key: String, _ value: some Any) {
        entries[key] = Entry(value: value, storedAt: .now)
    }

    func remove(_ key: String) {
        entries[key] = nil
    }

    func removeAll() {
        entries.removeAll()
    }
}
