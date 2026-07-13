import Foundation
import JarvisAPI
import Observation

/// Feature store for the Plan tab: the current block payload (block + week
/// scores + goals-with-tactics), the vision document, and every Stage 2
/// mutation (tactic week toggles, goal patches, vision edits).
@Observable
@MainActor
final class PlanStore {
    struct VisionContent {
        /// nil = no vision written yet (the server has none).
        var vision: VisionDTO?
        var areas: [AreaDTO]
    }

    private(set) var content: LoadState<CurrentBlockResponse> = .idle
    private(set) var visionContent: LoadState<VisionContent> = .idle
    /// Inline error from a failed mutation (data on screen stays valid).
    var mutationError: String?

    /// Optimistic completedWeeks overrides while a toggle round-trips.
    private var tacticWeekOverrides: [String: [Int]] = [:]

    private var model: AppModel?

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    // MARK: - Loading

    func load(force: Bool = false) async {
        guard let model else { return }
        if !force, let cached: CurrentBlockResponse = model.cache.get("blocks/current") {
            content = .loaded(cached)
            return
        }
        if content.value == nil { content = .loading }
        do {
            let response = try await model.api.currentBlock()
            content = .loaded(response)
            model.cache.set("blocks/current", response)
            tacticWeekOverrides = [:]
        } catch {
            model.handle(error)
            if content.value == nil {
                content = .failed(TodayStore.message(for: error))
            } else {
                mutationError = TodayStore.message(for: error)
            }
        }
    }

    /// Fetches the vision + areas once; `force` refetches after edits.
    func loadVision(force: Bool = false) async {
        guard let model else { return }
        if !force, visionContent.value != nil { return }
        if visionContent.value == nil { visionContent = .loading }
        do {
            async let areasResponse = model.api.areas()
            let vision: VisionDTO?
            do {
                vision = try await model.api.vision()
            } catch APIClientError.api(_, _, let status) where status == 404 {
                vision = nil
            }
            let areas = try await areasResponse.areas.filter { $0.archivedAt == nil }
            visionContent = .loaded(VisionContent(vision: vision, areas: areas))
        } catch {
            model.handle(error)
            if visionContent.value == nil {
                visionContent = .failed(TodayStore.message(for: error))
            } else {
                mutationError = TodayStore.message(for: error)
            }
        }
    }

    // MARK: - Derived

    var currentWeekNumber: Int? { content.value?.weekNumber }

    func goal(id: String) -> GoalWithProgressDTO? {
        content.value?.goals.first { $0.id == id }
    }

    func weekAvg(_ weekNumber: Int) -> Double? {
        content.value?.weekScores.first { $0.weekNumber == weekNumber }?.avg
    }

    /// Completed weeks for a tactic, with any in-flight optimistic override.
    func completedWeeks(for tactic: TacticDTO) -> [Int] {
        tacticWeekOverrides[tactic.id] ?? tactic.completedWeeks
    }

    /// Tactics applicable in a given week across all goals, paired with
    /// their goal (sorted by goal then tactic sortOrder).
    func tactics(forWeek weekNumber: Int) -> [(goal: GoalWithProgressDTO, tactic: TacticDTO)] {
        guard let goals = content.value?.goals else { return [] }
        return goals
            .sorted { $0.sortOrder < $1.sortOrder }
            .flatMap { goal in
                goal.tactics
                    .filter { $0.fromWeek <= weekNumber && weekNumber <= $0.toWeek }
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map { (goal, $0) }
            }
    }

    // MARK: - Mutations

    /// Optimistically flips a tactic-week, then syncs with the server.
    func setTacticWeek(_ tactic: TacticDTO, weekNumber: Int, done: Bool) async {
        guard let model else { return }
        var weeks = Set(completedWeeks(for: tactic))
        if done { weeks.insert(weekNumber) } else { weeks.remove(weekNumber) }
        tacticWeekOverrides[tactic.id] = weeks.sorted()
        do {
            let response = try await model.api.setTacticWeek(id: tactic.id, weekNumber: weekNumber, done: done)
            tacticWeekOverrides[tactic.id] = response.completedWeeks
            mutationError = nil
            await load() // refresh goal progress; clears overrides
        } catch {
            tacticWeekOverrides[tactic.id] = nil
            model.handle(error)
            mutationError = TodayStore.message(for: error)
        }
    }

    /// Patches a goal (trackStatus, manualProgress incl. `.null` to return
    /// to computed progress, description, status).
    func patchGoal(id: String, _ patch: JSONObject) async {
        await run { try await $0.patchGoal(id: id, patch) }
    }

    func createTactic(goalId: String, title: String, fromWeek: Int, toWeek: Int) async {
        await run { try await $0.createTactic(goalId: goalId, title: title, fromWeek: fromWeek, toWeek: toWeek) }
    }

    func deleteTactic(_ tactic: TacticDTO) async {
        await run { try await $0.deleteTactic(id: tactic.id) }
    }

    @discardableResult
    func saveVision(_ text: String) async -> Bool {
        guard let model else { return false }
        do {
            let updated = try await model.api.putVision(content: text)
            var next = visionContent.value ?? VisionContent(vision: nil, areas: [])
            next.vision = updated
            visionContent = .loaded(next)
            mutationError = nil
            return true
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
            return false
        }
    }

    @discardableResult
    func createBlock(title: String, startDate: DayKey) async -> Bool {
        guard let model else { return false }
        do {
            _ = try await model.api.createBlock(title: title, startDate: startDate)
            mutationError = nil
            model.invalidateToday()
            return true
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
            return false
        }
    }

    /// Runs a mutation; on success invalidates today so every open screen
    /// (including this one, via `todayRevision`) refetches.
    private func run<T: Sendable>(_ operation: (APIClient) async throws -> T) async {
        guard let model else { return }
        do {
            _ = try await operation(model.api)
            mutationError = nil
            model.invalidateToday()
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
        }
    }
}
