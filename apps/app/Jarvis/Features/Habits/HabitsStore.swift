import Foundation
import JarvisAPI
import Observation

/// Feature store for the Habits list: habits + areas + the Today payload
/// (per-habit reps/pace), plus a lazy per-habit stats cache for streak chips.
@Observable
@MainActor
final class HabitsStore {
    struct Content {
        var habits: [HabitDTO]
        var areas: [AreaDTO]
        var today: DayPayload
    }

    struct AreaGroup: Identifiable {
        let id: String
        let title: String
        let habits: [HabitDTO]
    }

    private(set) var content: LoadState<Content> = .idle
    /// Lazily loaded stats per habit id (streak chips). Missing = not loaded.
    private(set) var stats: [String: HabitStatsResponse] = [:]
    var mutationError: String?

    private var model: AppModel?

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    func load() async {
        guard let model else { return }
        if content.value == nil { content = .loading }
        do {
            async let habitsResponse = model.api.habits()
            async let areasResponse = model.api.areas()
            async let todayResponse = model.api.today()
            let (habitsList, areasList, today) = try await (habitsResponse, areasResponse, todayResponse)
            let loaded = Content(
                habits: habitsList.habits.filter { $0.archivedAt == nil },
                areas: areasList.areas.filter { $0.archivedAt == nil },
                today: today,
            )
            content = .loaded(loaded)
            loadStats(for: loaded.habits)
        } catch {
            model.handle(error)
            if content.value == nil {
                content = .failed(TodayStore.message(for: error))
            } else {
                mutationError = TodayStore.message(for: error)
            }
        }
    }

    /// Fires concurrent stats fetches for habits without a cached result.
    private func loadStats(for habits: [HabitDTO]) {
        guard let model else { return }
        for habit in habits where stats[habit.id] == nil {
            let id = habit.id
            Task {
                if let response = try? await model.api.habitStats(id: id) {
                    stats[id] = response
                }
            }
        }
    }

    /// Drops cached stats so the next load refetches them (after mutations).
    func invalidateStats(for habitId: String? = nil) {
        if let habitId {
            stats[habitId] = nil
        } else {
            stats = [:]
        }
    }

    // MARK: - Derived

    func todayEntry(for habitId: String) -> HabitTodayEntryDTO? {
        content.value?.today.habits.first { $0.habit.id == habitId }
    }

    var activeHabits: [HabitDTO] {
        (content.value?.habits ?? []).filter { $0.pausedAt == nil }
    }

    var pausedHabits: [HabitDTO] {
        (content.value?.habits ?? []).filter { $0.pausedAt != nil }
    }

    /// Active habits grouped by area (sorted by area sortOrder); habits with
    /// no matching area fall into a trailing "General" group.
    var groupedHabits: [AreaGroup] {
        guard let content = content.value else { return [] }
        let active = activeHabits
        var groups: [AreaGroup] = []
        for area in content.areas.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let habits = active.filter { $0.areaId == area.id }.sorted { $0.sortOrder < $1.sortOrder }
            if !habits.isEmpty {
                groups.append(AreaGroup(id: area.id, title: area.name, habits: habits))
            }
        }
        let areaIds = Set(content.areas.map(\.id))
        let general = active
            .filter { $0.areaId == nil || !areaIds.contains($0.areaId ?? "") }
            .sorted { $0.sortOrder < $1.sortOrder }
        if !general.isEmpty {
            groups.append(AreaGroup(id: "general", title: "General", habits: general))
        }
        return groups
    }

    /// Header strip numbers: habits on pace vs all active habits with a
    /// Today entry (weekly on pace/done, daily/multi at full credit today).
    var paceSummary: (onPace: Int, total: Int, flags: [Bool]) {
        guard let today = content.value?.today else { return (0, 0, []) }
        let activeIds = Set(activeHabits.map(\.id))
        let entries = today.habits.filter { activeIds.contains($0.habit.id) }
        let flags = entries.map { HabitDisplay.isOnPace($0) }
        return (flags.filter { $0 }.count, flags.count, flags)
    }

    // MARK: - Mutations

    func logHabit(_ habitId: String) async {
        await run(invalidatingStatsFor: habitId) { try await $0.logHabit(id: habitId) }
    }

    func unlogHabit(_ habitId: String) async {
        await run(invalidatingStatsFor: habitId) { try await $0.unlogHabit(id: habitId) }
    }

    func setPaused(_ habit: HabitDTO, paused: Bool) async {
        await run { try await $0.patchHabit(id: habit.id, ["paused": .bool(paused)]) }
    }

    func archive(_ habit: HabitDTO) async {
        await run { try await $0.archiveHabit(id: habit.id) }
    }

    private func run<T: Sendable>(
        invalidatingStatsFor habitId: String? = nil,
        _ operation: (APIClient) async throws -> T,
    ) async {
        guard let model else { return }
        do {
            _ = try await operation(model.api)
            mutationError = nil
            if let habitId { invalidateStats(for: habitId) }
            model.invalidateToday()
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
        }
    }
}
