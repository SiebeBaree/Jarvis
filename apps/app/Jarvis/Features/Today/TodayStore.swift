import Foundation
import JarvisAPI
import Observation

/// Feature store for the Today screen.
///
/// Local-first: the screen renders from `LocalStore` (which survives
/// relaunches) and revalidates behind that, so opening the app never shows a
/// spinner for data this device has seen before. Mutations apply to the local
/// payload immediately, are written back to `LocalStore`, and are handed to
/// the offline queue — nothing here awaits the network, so a tap is never
/// slower than a frame, and a change made offline is still there after a
/// relaunch.
@Observable
@MainActor
final class TodayStore {
    private(set) var day: LoadState<DayPayload> = .idle
    /// Inline error from a failed load (data on screen stays valid).
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

        if !force, day.value == nil,
           let cached = model.store.read(DayPayload.self, .today) {
            // Only today's payload is usable — an older one would show the
            // wrong day. A stale-but-correct-day payload still paints, then
            // revalidates below.
            let boundary = model.settings?.dayBoundaryHour ?? 3
            if cached.value.dayKey == DayKeyMath.todayKey(boundaryHour: boundary) {
                day = .loaded(cached.value)
                model.updatePlanContext(
                    weekNumber: cached.value.weekNumber,
                    isReviewWeek: cached.value.isReviewWeek,
                )
                if cached.isFresh { return }
            }
        }
        if day.value == nil { day = .loading }

        do {
            let payload = try await model.api.today()
            apply(payload)
            model.updatePlanContext(weekNumber: payload.weekNumber, isReviewWeek: payload.isReviewWeek)
            mutationError = nil
        } catch {
            model.handle(error)
            if day.value == nil {
                day = .failed(Self.message(for: error))
            } else {
                // Something is already on screen — keep it and stay quiet
                // unless the user has no data at all.
                mutationError = Self.message(for: error)
            }
        }
    }

    /// Sets the payload and mirrors it to the local store, so both a cold
    /// launch and an offline edit come back to exactly what was on screen.
    private func apply(_ payload: DayPayload) {
        day = .loaded(payload)
        model?.store.write(payload, .today)
    }

    // MARK: - Tasks

    func completeTask(_ task: TaskDTO) {
        setTaskStatus(task, to: .done)
    }

    func uncompleteTask(_ task: TaskDTO) {
        setTaskStatus(task, to: .open)
    }

    private func setTaskStatus(_ task: TaskDTO, to status: TaskStatus) {
        guard var payload = day.value else { return }
        let updated = task.with(status: status)
        payload.tasksDue = payload.tasksDue.map { $0.id == task.id ? updated : $0 }
        payload.overdueTasks = status == .done
            ? payload.overdueTasks.filter { $0.id != task.id }
            : payload.overdueTasks
        apply(payload)
        model?.mutate(
            "POST",
            "/tasks/\(task.id)/\(status == .done ? "complete" : "uncomplete")",
            entities: [.task, .score],
            label: "\"\(task.title)\"",
        )
    }

    func rescheduleTask(_ task: TaskDTO, to dayKey: DayKey) {
        guard var payload = day.value else { return }
        // Rescheduling moves the task off today's lists — reflect instantly.
        if dayKey != payload.dayKey {
            payload.tasksDue = payload.tasksDue.filter { $0.id != task.id }
            payload.overdueTasks = payload.overdueTasks.filter { $0.id != task.id }
            apply(payload)
        }
        model?.mutate(
            "PATCH",
            "/tasks/\(task.id)",
            body: ["dueDate": JSONValue.string(dayKey)],
            entities: [.task, .score],
            label: "\"\(task.title)\"",
        )
    }

    /// The quick-add composer.
    func createQuickTask(title: String, dueDate: String?, priority: TaskPriority, categoryId: String? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        createTask(
            TaskCreateRequest(
                id: UUID().uuidString,
                title: trimmed,
                dueDate: dueDate,
                priority: priority,
                categoryId: categoryId,
            ),
        )
    }

    /// Creates a task with a client-generated id, so the row appears with the
    /// id it will keep on the server — immediately completable, and safe for
    /// the queue to replay.
    func createTask(_ request: TaskCreateRequest) {
        let id = request.id ?? UUID().uuidString
        var withId = request
        withId.id = id
        if var payload = day.value, request.dueDate == payload.dayKey {
            payload.tasksDue.append(
                .locallyCreated(
                    id: id,
                    title: request.title,
                    notes: request.notes,
                    dueDate: request.dueDate,
                    dueTime: request.dueTime,
                    priority: request.priority ?? .medium,
                    goalId: request.goalId,
                    categoryId: request.categoryId,
                ),
            )
            apply(payload)
        }
        model?.mutate(
            "POST",
            "/tasks",
            body: withId,
            entities: [.task, .score],
            label: "\"\(request.title)\"",
        )
    }

    // MARK: - Habits

    func logHabit(_ habitId: String, dayKey: DayKey? = nil) {
        adjustHabit(habitId, dayKey: dayKey, delta: 1)
    }

    func unlogHabit(_ habitId: String, dayKey: DayKey? = nil) {
        adjustHabit(habitId, dayKey: dayKey, delta: -1)
    }

    private func adjustHabit(_ habitId: String, dayKey: DayKey?, delta: Int) {
        guard let payload = day.value else { return }
        let name = payload.habits.first { $0.habit.id == habitId }?.habit.name ?? "habit"

        // Only today's payload is on screen; backdated logs skip the flip.
        if dayKey == nil || dayKey == payload.dayKey {
            var next = payload
            next.habits = next.habits.map {
                $0.habit.id == habitId ? $0.adjustingReps(by: delta) : $0
            }
            apply(next)
        }

        if delta > 0 {
            model?.mutate(
                "POST",
                "/habits/\(habitId)/log",
                // The rep's own id: logging inserts a row, so a replay without
                // this would silently count the habit twice.
                body: HabitLogPayload(dayKey: dayKey, completionId: UUID().uuidString),
                entities: [.habit, .score],
                label: name,
            )
        } else {
            model?.mutate(
                "DELETE",
                "/habits/\(habitId)/log",
                body: HabitLogPayload(dayKey: dayKey, completionId: nil),
                entities: [.habit, .score],
                label: name,
            )
        }
    }

    private nonisolated struct HabitLogPayload: Encodable, Sendable {
        let dayKey: DayKey?
        let completionId: String?
    }

    // MARK: - Mood

    func setMood(_ value: Int) {
        guard var payload = day.value else { return }
        let dayKey = payload.dayKey
        payload.mood = MoodDTO(optimisticValue: value)
        apply(payload)
        model?.mutate(
            "PUT",
            "/mood/\(dayKey)",
            body: MoodPutRequest(value: value),
            entities: [.mood, .score],
            label: "today's mood",
        )
    }

    func setYesterdayMood(_ value: Int) {
        guard let payload else { return }
        let yesterday = DayKeyMath.addDays(payload.dayKey, -1)
        backfillSkipped = true // the row's job is done either way
        model?.mutate(
            "PUT",
            "/mood/\(yesterday)",
            body: MoodPutRequest(value: value),
            entities: [.mood, .score],
            label: "yesterday's mood",
        )
    }

    static func message(for error: Error) -> String {
        (error as? APIClientError)?.errorDescription ?? "Something went wrong."
    }
}
