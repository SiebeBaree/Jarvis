import Foundation
import JarvisAPI
import Observation

@Observable
final class AppModel {
    enum SessionState {
        case checking
        case loggedOut
        case loggedIn(UserDTO, SettingsDTO)
    }

    let api: APIClient
    /// The device's own copy of server state — reads render from here first.
    let store = LocalStore()
    /// Writes waiting to reach the server (survives relaunch and offline).
    let queue = MutationQueue()
    private(set) var session: SessionState = .checking

    /// Bumped when server state has actually changed underneath the screens,
    /// so they revalidate. Deliberately NOT bumped for local optimistic edits:
    /// the screen that made the edit already shows the result, and the others
    /// pick it up when the write lands.
    private(set) var dataRevision = 0

    /// Cross-tab navigation requests (empty states → Habits, Goals...).
    /// MainShell consumes and clears it.
    var requestedSection: AppSection?

    /// Bumped by every local write. A fetch that was already in flight when a
    /// write happened is answering an older question: applying its response
    /// would wipe the optimistic change off the screen until the next refresh
    /// put it back — the flicker you get tapping two habits in a row. Stores
    /// capture this before fetching and discard the response if it moved.
    private(set) var writeTicket = 0

    init() {
        self.api = APIClient(baseURL: Config.apiBaseURL)
    }

    /// Starts the outbox. Called once the session is known so queued writes
    /// from a previous launch flush with a valid token.
    @MainActor
    private func startQueue() {
        queue.configure(api: api) { [weak self] entities in
            self?.invalidate(entities)
        }
    }

    // MARK: - Writes

    /// Records a write that has already been applied to local state. Returns
    /// immediately: it is persisted to the outbox and sent in the background,
    /// so no tap ever waits on the network.
    ///
    /// Every call must be safe to send twice — the queue replays on retry and
    /// after relaunch. Creates therefore carry a client-generated id, and
    /// patches send absolute values.
    @MainActor
    func mutate(
        _ method: String,
        _ path: String,
        body: (some Encodable & Sendable)? = nil as EmptyEncodable?,
        entities: Set<Entity>,
        label: String,
    ) {
        // Local state is already ahead of the caches, so mark them stale now;
        // the revision bump waits until the server confirms.
        writeTicket &+= 1
        store.invalidate(entities)
        queue.enqueue(method: method, path: path, body: body, entities: entities, label: label)
    }

    // MARK: - Task categories
    //
    // One shared, cached list. The quick-add chips need categories the moment
    // the composer opens, so every screen reads them from here instead of
    // firing its own `GET /task-categories` on appear.

    private(set) var categories: [TaskCategoryDTO] = []
    private var categoriesLoad: Task<Void, Never>?

    @MainActor
    func loadCategories(force: Bool = false) async {
        if let cached = store.read([TaskCategoryDTO].self, .taskCategories) {
            categories = cached.value
            if cached.isFresh, !force { return }
        }
        if let inFlight = categoriesLoad {
            await inFlight.value
            return
        }
        let load = Task { [weak self] in
            guard let self, let response = try? await api.taskCategories() else { return }
            categories = response.categories
            store.write(response.categories, .taskCategories)
        }
        categoriesLoad = load
        await load.value
        categoriesLoad = nil
    }

    /// Creates a category (or hands back the one that already has that name —
    /// quick-add types names, and a near-duplicate list is worse than a reuse).
    @MainActor
    @discardableResult
    func createCategory(name: String) async -> TaskCategoryDTO? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = categories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        guard let created = try? await api.createTaskCategory(
            TaskCategoryCreateRequest(name: trimmed, colorHex: CategoryPalette.next(after: categories.count)),
        ) else { return nil }
        categories.append(created)
        // Invalidate first, then write: the lists that show categories need a
        // refetch, but this list is already correct.
        invalidate([.category])
        store.write(categories, .taskCategories)
        return created
    }

    /// True when a write landed since `ticket` was taken, meaning a response
    /// fetched under that ticket is already out of date.
    @MainActor
    func hasWritten(since ticket: Int) -> Bool { writeTicket != ticket }

    /// Marks the caches depending on `entities` stale and asks open screens to
    /// revalidate. Cached values are kept, so revalidation never blanks a screen.
    @MainActor
    func invalidate(_ entities: Set<Entity>) {
        store.invalidate(entities)
        scheduleRevalidation()
    }

    /// Blanket invalidation for callers that predate entity tracking.
    @MainActor
    func invalidateToday() {
        invalidate(Entity.all)
    }

    /// Trailing-edge debounce: a burst of landing writes triggers one refresh.
    private var revalidation: Task<Void, Never>?

    /// How long to wait for the outbox before giving up on this round of
    /// revalidation. Anything still queued after that is offline or wedged;
    /// the next landing write schedules a fresh attempt.
    private static let drainTimeout = 15

    @MainActor
    private func scheduleRevalidation() {
        revalidation?.cancel()
        revalidation = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            // Revalidating with writes still queued refetches server state
            // that predates them — the screen would drop the optimistic value
            // and only get it back on the next refresh. Wait them out.
            var waited = 0
            while queue.hasPending {
                guard waited < Self.drainTimeout else { return }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                waited += 1
            }
            dataRevision += 1
        }
    }

    // MARK: - Session lifecycle

    #if DEBUG
    /// Debug-only: `-jarvisToken <raw>` seeds the session from a launch
    /// argument. Reinstalling on the simulator clears its keychain, so every
    /// rebuild otherwise lands on the sign-in screen — this lets a dev (or an
    /// agent) attach an already-created session instead of retyping a
    /// password. Compiled out of Release entirely.
    private static var launchArgumentToken: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-jarvisToken"),
              arguments.index(after: flag) < arguments.endIndex
        else { return nil }
        let token = arguments[arguments.index(after: flag)]
        return token.isEmpty ? nil : token
    }
    #endif

    @MainActor
    func bootstrap() async {
        var stored = Keychain.loadToken()
        #if DEBUG
        if let injected = Self.launchArgumentToken, injected != stored {
            Keychain.saveToken(injected)
            stored = injected
        }
        #endif
        guard let token = stored else {
            session = .loggedOut
            return
        }
        await api.setToken(token)
        // Queued writes and cached reads belong to this token — start the
        // outbox before the network check so an offline launch still drains
        // once connectivity returns.
        startQueue()
        do {
            let me = try await api.me()
            session = .loggedIn(me.user, me.settings)
        } catch APIClientError.unauthorized {
            Keychain.deleteToken()
            await api.setToken(nil)
            session = .loggedOut
        } catch {
            // Server unreachable — keep the token, stay on a retry screen.
            session = .loggedOut
        }
    }

    @MainActor
    func signIn(email: String, password: String, register: Bool) async throws {
        let deviceName = Self.deviceName
        let auth: AuthResponse = register
            ? try await api.register(email: email, password: password)
            : try await api.login(email: email, password: password, deviceName: deviceName)
        Keychain.saveToken(auth.token)
        await api.setToken(auth.token)
        let me = try await api.me()
        session = .loggedIn(me.user, me.settings)
        startQueue()
    }

    @MainActor
    func signOut() async {
        _ = try? await api.logout()
        Keychain.deleteToken()
        await api.setToken(nil)
        revalidation?.cancel()
        // Explicit sign-out is the one place queued writes are dropped — a 401
        // does not, so an expired session re-syncs after signing back in.
        queue.clear()
        store.clear()
        categories = []
        session = .loggedOut
    }

    /// Central handler: any 401 from a feature store funnels here.
    @MainActor
    func handle(_ error: Error) {
        if case APIClientError.unauthorized = error {
            Keychain.deleteToken()
            Task { await api.setToken(nil) }
            session = .loggedOut
        }
    }

    @MainActor
    func refreshSettings() async {
        guard case .loggedIn(let user, _) = session else { return }
        if let settings = try? await api.settings() {
            session = .loggedIn(user, settings)
        }
    }

    var settings: SettingsDTO? {
        if case .loggedIn(_, let settings) = session { return settings }
        return nil
    }

    static var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        "iPhone"
        #endif
    }
}
