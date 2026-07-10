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
    private(set) var session: SessionState = .checking

    /// Bumped after any mutation so open screens (Today especially) refetch.
    private(set) var todayRevision = 0

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

    func invalidateToday() {
        todayRevision += 1
    }

    func updatePlanContext(weekNumber: Int?, isReviewWeek: Bool) {
        let next = PlanContext(weekNumber: weekNumber, isReviewWeek: isReviewWeek)
        if next != planContext { planContext = next }
    }

    // MARK: - Session lifecycle

    func bootstrap() async {
        guard let token = Keychain.loadToken() else {
            session = .loggedOut
            return
        }
        await api.setToken(token)
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
    }

    func signOut() async {
        _ = try? await api.logout()
        Keychain.deleteToken()
        await api.setToken(nil)
        session = .loggedOut
    }

    /// Central handler: any 401 from a feature store funnels here.
    func handle(_ error: Error) {
        if case APIClientError.unauthorized = error {
            Keychain.deleteToken()
            Task { await api.setToken(nil) }
            session = .loggedOut
        }
    }

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
