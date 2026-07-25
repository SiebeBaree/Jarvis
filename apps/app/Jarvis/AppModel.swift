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

    /// Cross-tab navigation requests (week chip → Plan, empty states → Habits...).
    /// MainShell consumes and clears it.
    var requestedSection: AppSection?

    /// Live block context for the macOS sidebar label; TodayStore updates it.
    struct PlanContext: Equatable {
        var weekNumber: Int?
        var isReviewWeek: Bool
    }

    private(set) var planContext = PlanContext(weekNumber: nil, isReviewWeek: false)

    /// True right after account creation — triggers the automatic first-run interview.
    var needsFirstRunOnboarding = false

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
        store.invalidate(entities)
        queue.enqueue(method: method, path: path, body: body, entities: entities, label: label)
    }

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

    @MainActor
    private func scheduleRevalidation() {
        revalidation?.cancel()
        revalidation = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.dataRevision += 1
        }
    }

    func updatePlanContext(weekNumber: Int?, isReviewWeek: Bool) {
        let next = PlanContext(weekNumber: weekNumber, isReviewWeek: isReviewWeek)
        if next != planContext { planContext = next }
    }

    // MARK: - Session lifecycle

    @MainActor
    func bootstrap() async {
        guard let token = Keychain.loadToken() else {
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
        needsFirstRunOnboarding = register // first run: account → interview (§B4)
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
