import Foundation
import JarvisAPI
import Observation

/// Feature store for the Today screen. Fetches the one-shot day payload and
/// exposes mutation helpers. Habit logs, task completion, and mood commit
/// optimistically: the UI flips instantly, the API call runs behind it, and
/// a failure rolls the change back with an inline error. Every successful
/// mutation bumps `model.todayRevision` (which also clears the request
/// cache), so all open screens silently refetch true state.
@Observable
@MainActor
final class TodayStore {
    private static let cacheKey = "days/today"
    /// Same payload on disk; the memory key has a "/" and can't be a filename.
    private static let diskKey = "day-today"

    private(set) var day: LoadState<DayPayload> = .idle
    /// Inline error from a failed mutation (data on screen stays valid).
    var mutationError: String?
    /// Session-only "Skip" for the yesterday-mood backfill row.
    var backfillSkipped = false

    private var model: AppModel?
    /// The fetch currently in flight — launch fires `.task` and the
    /// scenePhase-active change back to back, and every extra caller here
    /// used to mean another full payload request.
    private var inFlight: Task<Void, Never>?

    var payload: DayPayload? { day.value }

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    func load(force: Bool = false) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await fetch(force: force) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func fetch(force: Bool) async {
        guard let model else { return }
        if !force, day.value == nil, let cached: DayPayload = model.cache.get(Self.cacheKey) {
            day = .loaded(cached)
            model.updatePlanContext(weekNumber: cached.weekNumber, isReviewWeek: cached.isReviewWeek)
            return
        }
        // Cold launch: paint last session's payload right away, then refresh
        // behind it. Only today's — an older one would show the wrong day.
        if day.value == nil {
            let boundary = model.settings?.dayBoundaryHour ?? 3
            if let stored = DiskCache.load(DayPayload.self, Self.diskKey),
               stored.dayKey == DayKeyMath.todayKey(boundaryHour: boundary) {
                day = .loaded(stored)
                model.updatePlanContext(weekNumber: stored.weekNumber, isReviewWeek: stored.isReviewWeek)
            } else {
                day = .loading
            }
        }
        do {
            let payload = try await model.api.today()
            day = .loaded(payload)
            model.cache.set(Self.cacheKey, payload)
            DiskCache.save(payload, Self.diskKey)
            model.updatePlanContext(weekNumber: payload.weekNumber, isReviewWeek: payload.isReviewWeek)
        } catch {
            model.handle(error)
            if day.value == nil {
                day = .failed(Self.message(for: error))
            } else {
                mutationError = Self.message(for: error)
            }
        }
    }

    // MARK: - Tasks (optimistic)

    func completeTask(_ task: TaskDTO) async {
        await setTaskStatus(task, to: .done) { try await $0.completeTask(id: task.id) }
    }

    func uncompleteTask(_ task: TaskDTO) async {
        await setTaskStatus(task, to: .open) { try await $0.uncompleteTask(id: task.id) }
    }

    private func setTaskStatus(
        _ task: TaskDTO,
        to status: TaskStatus,
        _ operation: (APIClient) async throws -> some Sendable,
    ) async {
        let original = day.value
        if var payload = day.value {
            let updated = task.with(status: status)
            payload.tasksDue = payload.tasksDue.map { $0.id == task.id ? updated : $0 }
            payload.overdueTasks = status == .done
                ? payload.overdueTasks.filter { $0.id != task.id }
                : payload.overdueTasks
            day = .loaded(payload)
        }
        await run(rollbackTo: original, operation)
    }

    func rescheduleTask(_ task: TaskDTO, to dayKey: DayKey) async {
        // Rescheduling moves the task off today's lists — reflect instantly.
        let original = day.value
        if var payload = day.value, dayKey != payload.dayKey {
            payload.tasksDue = payload.tasksDue.filter { $0.id != task.id }
            payload.overdueTasks = payload.overdueTasks.filter { $0.id != task.id }
            day = .loaded(payload)
        }
        await run(rollbackTo: original) { try await $0.patchTask(id: task.id, ["dueDate": .string(dayKey)]) }
    }

    func createQuickTask(title: String, dueDate: String?, priority: TaskPriority, categoryId: String? = nil) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Creation needs the server-issued id — no optimistic row.
        await run(rollbackTo: nil) {
            try await $0.createTask(
                TaskCreateRequest(title: trimmed, dueDate: dueDate, priority: priority, categoryId: categoryId),
            )
        }
    }

    // MARK: - Habits (optimistic)

    func logHabit(_ habitId: String, dayKey: DayKey? = nil) async {
        await adjustHabit(habitId, dayKey: dayKey, delta: 1) { try await $0.logHabit(id: habitId, dayKey: dayKey) }
    }

    func unlogHabit(_ habitId: String, dayKey: DayKey? = nil) async {
        await adjustHabit(habitId, dayKey: dayKey, delta: -1) { try await $0.unlogHabit(id: habitId, dayKey: dayKey) }
    }

    private func adjustHabit(
        _ habitId: String,
        dayKey: DayKey?,
        delta: Int,
        _ operation: (APIClient) async throws -> some Sendable,
    ) async {
        let original = day.value
        // Only today's payload is on screen; backdated logs skip the flip.
        if var payload = day.value, dayKey == nil || dayKey == payload.dayKey {
            payload.habits = payload.habits.map {
                $0.habit.id == habitId ? $0.adjustingReps(by: delta) : $0
            }
            day = .loaded(payload)
        }
        await run(rollbackTo: original, operation)
    }

    // MARK: - Mood (optimistic)

    func setMood(_ value: Int) async {
        let original = day.value
        if var payload = day.value {
            payload.mood = MoodDTO(optimisticValue: value)
            day = .loaded(payload)
        }
        guard let dayKey = original?.dayKey else { return }
        await run(rollbackTo: original) { try await $0.putMood(dayKey: dayKey, value: value) }
    }

    func setYesterdayMood(_ value: Int) async {
        guard let payload else { return }
        let yesterday = DayKeyMath.addDays(payload.dayKey, -1)
        await run(rollbackTo: nil) { try await $0.putMood(dayKey: yesterday, value: value) }
    }

    // MARK: - Plumbing

    /// Runs a mutation; on success clears the inline error and invalidates
    /// today (cache cleared + every open screen refetches true state, which
    /// also updates the score ring). On failure restores `rollbackTo`.
    private func run<T: Sendable>(
        rollbackTo original: DayPayload?,
        _ operation: (APIClient) async throws -> T,
    ) async {
        guard let model else { return }
        do {
            _ = try await operation(model.api)
            mutationError = nil
            model.invalidateToday()
        } catch {
            model.handle(error)
            if let original { day = .loaded(original) }
            mutationError = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        (error as? APIClientError)?.errorDescription ?? "Something went wrong."
    }
}
