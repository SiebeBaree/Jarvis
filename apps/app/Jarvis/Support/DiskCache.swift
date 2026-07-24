import Foundation

/// Tiny JSON-on-disk cache that survives app launches.
///
/// The in-memory `RequestCache` only helps within one run, so a cold launch
/// always stared at a spinner while `/days/today` came back. Today's payload
/// is written here after every successful fetch and rendered immediately on
/// the next launch, with the network refresh happening behind it.
enum DiskCache {
    private static let directory: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let url = base.appending(path: "JarvisCache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static func url(_ name: String) -> URL? {
        directory?.appending(path: "\(name).json")
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Encodes and writes off the main actor — callers are on it.
    static func save(_ value: some Encodable & Sendable, _ name: String) {
        guard let url = url(name) else { return }
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    static func removeAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
