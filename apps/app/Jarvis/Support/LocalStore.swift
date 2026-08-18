import Foundation

/// A domain entity that cached responses can depend on. A mutation declares
/// which entities it touched; only the cache entries that actually depend on
/// one of them go stale.
enum Entity: String, Codable, Sendable {
    case task
    case habit
    case mood
    case goal
    case category
    case area
    case score
    case metric
    case improvement
    case exercise
    case routine
    case workout
    case shopping
    case meal

    /// For the "something changed, I don't know what" callers that predate
    /// entity tracking — behaves like the old blanket invalidation.
    static let all: Set<Entity> = [
        .task, .habit, .mood, .goal, .category, .area, .score, .metric, .improvement,
        .exercise, .routine, .workout, .shopping, .meal,
    ]
}

/// One cached GET response. The case list is the app's whole read surface,
/// which is what makes dependency-based invalidation possible: every key
/// states what it is built from.
enum CacheKey: Hashable, Sendable {
    case today
    case tasks(segment: String)
    case goals
    case taskCategories
    case areas
    case habits
    case metrics
    case improvementAreas
    case trendScores(range: String)
    case trendWeekly
    case trendHeatmap
    case exercises
    case routines
    case workoutSessions
    /// Per-session, so an in-progress workout survives a relaunch in a gym
    /// basement with no signal.
    case workoutSession(id: String)
    case shoppingList
    case mealPreps

    /// Stable, filename-safe identity for the on-disk copy.
    var filename: String {
        switch self {
        case .today: "today"
        case .tasks(let segment): "tasks-\(segment)"
        case .goals: "goals"
        case .taskCategories: "task-categories"
        case .areas: "areas"
        case .habits: "habits"
        case .metrics: "metrics"
        case .improvementAreas: "improvement-areas"
        case .trendScores(let range): "trend-scores-\(range)"
        case .trendWeekly: "trend-weekly"
        case .trendHeatmap: "trend-heatmap"
        case .exercises: "exercises"
        case .routines: "routines"
        case .workoutSessions: "workout-sessions"
        case .workoutSession(let id): "workout-session-\(id)"
        case .shoppingList: "shopping-list"
        case .mealPreps: "meal-preps"
        }
    }

    /// Mutating any of these makes this entry stale.
    var entities: Set<Entity> {
        switch self {
        case .today: [.task, .habit, .mood, .score]
        case .tasks: [.task, .category]
        case .goals: [.goal]
        case .taskCategories: [.category]
        case .areas: [.area]
        case .habits: [.habit]
        case .metrics: [.metric]
        case .improvementAreas: [.improvement]
        case .trendScores, .trendWeekly, .trendHeatmap: [.score, .habit, .mood, .task]
        case .exercises: [.exercise]
        // A routine card shows its exercise count, so renaming or deleting an
        // exercise has to invalidate the routine list too.
        case .routines: [.routine, .exercise, .workout]
        case .workoutSessions: [.workout]
        case .workoutSession: [.workout]
        case .shoppingList: [.shopping]
        case .mealPreps: [.meal]
        }
    }
}

/// The app's local copy of server state — the thing that makes Jarvis feel
/// offline. Two rules make it work:
///
/// 1. **Nothing is ever evicted.** Reads always return the last known value,
///    however old, so a screen can paint immediately instead of spinning.
///    Freshness is reported alongside so the caller knows to revalidate.
/// 2. **Invalidation is targeted.** Completing a task marks the task-shaped
///    entries stale; it does not throw away habits, the plan, or the vision
///    (which is what a blanket `removeAll()` used to do, forcing every open
///    screen to refetch everything after every tap).
///
/// Entries are mirrored to disk, so a cold launch starts from the last state
/// the device saw rather than from an empty screen. Optimistic changes are
/// written here too — an edit made offline survives a relaunch, and the
/// pending request that goes with it lives in `MutationQueue`.
@MainActor
final class LocalStore {
    /// How long a freshly fetched entry is trusted before a screen revisit
    /// revalidates it. Stale entries still render — they just trigger a fetch.
    static let freshWindow: TimeInterval = 120

    private struct Entry {
        var json: Data
        var storedAt: Date
        /// Set by `invalidate` — the value stays readable, but callers are
        /// told to refetch.
        var isStale: Bool
    }

    private var entries: [CacheKey: Entry] = [:]
    /// Keys already looked for on disk, so a miss costs one filesystem hit.
    private var diskChecked: Set<CacheKey> = []

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private static let directory: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let url = base.appending(path: "JarvisStore", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func fileURL(_ key: CacheKey) -> URL? {
        Self.directory?.appending(path: "\(key.filename).json")
    }

    // MARK: - Reading

    /// The last known value for `key`, plus whether it is fresh enough to
    /// skip a refetch. Returns nil only when this device has never seen it.
    func read<T: Decodable>(_ type: T.Type, _ key: CacheKey) -> (value: T, isFresh: Bool)? {
        if entries[key] == nil, !diskChecked.contains(key) {
            diskChecked.insert(key)
            if let url = fileURL(key),
               let data = try? Data(contentsOf: url),
               let stored = try? decoder.decode(DiskEnvelope.self, from: data) {
                // Disk survivals start stale: the app may have been closed for
                // days, so paint them, then immediately revalidate.
                entries[key] = Entry(json: stored.json, storedAt: stored.storedAt, isStale: true)
            }
        }
        guard let entry = entries[key], let value = try? decoder.decode(T.self, from: entry.json) else {
            return nil
        }
        let isFresh = !entry.isStale && Date.now.timeIntervalSince(entry.storedAt) < Self.freshWindow
        return (value, isFresh)
    }

    // MARK: - Writing

    /// Records a value as the current truth for `key` — used both for server
    /// responses and for optimistic local edits.
    func write(_ value: some Encodable, _ key: CacheKey) {
        guard let json = try? encoder.encode(value) else { return }
        entries[key] = Entry(json: json, storedAt: .now, isStale: false)
        diskChecked.insert(key)
        persist(json, key)
    }

    private func persist(_ json: Data, _ key: CacheKey) {
        guard let url = fileURL(key) else { return }
        let envelope = DiskEnvelope(json: json, storedAt: .now)
        guard let data = try? encoder.encode(envelope) else { return }
        // Off the main actor: encoding is done, only the write is left.
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private struct DiskEnvelope: Codable {
        let json: Data
        let storedAt: Date
    }

    // MARK: - Invalidation

    /// Marks every entry depending on one of `entities` as needing a refetch.
    /// Values are deliberately kept so screens keep rendering meanwhile.
    func invalidate(_ entities: Set<Entity>) {
        for (key, var entry) in self.entries where !key.entities.isDisjoint(with: entities) {
            entry.isStale = true
            self.entries[key] = entry
        }
    }

    /// Sign-out: drop everything, memory and disk.
    func clear() {
        entries.removeAll()
        diskChecked.removeAll()
        guard let directory = Self.directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
