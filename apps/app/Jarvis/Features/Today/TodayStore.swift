import Foundation
import JarvisAPI
import Observation

/// Feature store for the Today screen, which shows today plus the three days
/// behind it (`TodayStore.reachableDays`).
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
    /// How far back the day pager reaches: today and the three days before it.
    /// Far enough to catch up on a weekend, short enough that the score stays
    /// a record of what happened rather than something you fill in later.
    static let reachableDays = 4

    private(set) var day: LoadState<DayPayload> = .idle
    /// Payloads for past days, keyed by dayKey. Only today's lives in `day`,
    /// because only today's is worth persisting across launches.
    private(set) var pastDays: [DayKey: LoadState<DayPayload>] = [:]
    /// Inline error from a failed load (data on screen stays valid).
    var mutationError: String?

    private var model: AppModel?
    /// The fetch currently in flight — launch fires `.task` and the
    /// scenePhase-active change back to back, and every extra caller here
    /// used to mean another full payload request.
    private var inFlight: Task<Void, Never>?
    private var pastInFlight: Set<DayKey> = []

    var payload: DayPayload? { day.value }

    /// Today first, then yesterday, then the two days before it.
    var reachableDayKeys: [DayKey] {
        guard let today = day.value?.dayKey else { return [] }
        return (0..<Self.reachableDays).map { DayKeyMath.addDays(today, -$0) }
    }

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    /// The payload for any reachable day — today's comes from `day`.
    func payload(for dayKey: DayKey) -> DayPayload? {
        dayKey == day.value?.dayKey ? day.value : pastDays[dayKey]?.value
    }

    func state(for dayKey: DayKey) -> LoadState<DayPayload> {
        dayKey == day.value?.dayKey ? day : (pastDays[dayKey] ?? .idle)
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
                if cached.isFresh { return }
            }
        }
        if day.value == nil { day = .loading }

        // Taken before the request so a write made while it is in flight can
        // be detected on arrival — see AppModel.writeTicket.
        let ticket = model.writeTicket
        do {
            let payload = try await model.api.today()
            guard !model.hasWritten(since: ticket) else { return }
            apply(payload)
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

    /// Warms the three back-days concurrently. The day strip shows each day's
    /// score, and a strip of "—" reads as broken rather than as "not fetched
    /// yet" — so they are pulled as soon as today lands, not on navigation.
    /// Fire-and-forget: nothing on screen is waiting for them.
    func prefetchReachableDays(force: Bool = false) {
        for dayKey in reachableDayKeys.dropFirst() {
            Task { await loadPast(dayKey, force: force) }
        }
    }

    /// Fetches one of the three past days the pager can reach. Past payloads
    /// are memory-only: they are cheap to refetch and never the first thing
    /// on screen at launch.
    func loadPast(_ dayKey: DayKey, force: Bool = false) async {
        guard let model, dayKey != day.value?.dayKey else { return }
        if !force, pastDays[dayKey]?.value != nil { return }
        guard !pastInFlight.contains(dayKey) else { return }
        pastInFlight.insert(dayKey)
        defer { pastInFlight.remove(dayKey) }

        if pastDays[dayKey]?.value == nil { pastDays[dayKey] = .loading }
        let ticket = model.writeTicket
        do {
            let payload = try await model.api.day(dayKey)
            guard !model.hasWritten(since: ticket) else { return }
            pastDays[dayKey] = .loaded(payload)
        } catch {
            model.handle(error)
            if pastDays[dayKey]?.value == nil {
                pastDays[dayKey] = .failed(Self.message(for: error))
            }
        }
    }

    /// Sets the payload and mirrors it to the local store, so both a cold
    /// launch and an offline edit come back to exactly what was on screen.
    private func apply(_ payload: DayPayload) {
        day = .loaded(payload)
        model?.store.write(payload, .today)
    }

    /// Writes an edited payload back to whichever slot it came from.
    private func apply(_ payload: DayPayload, for dayKey: DayKey) {
        if dayKey == day.value?.dayKey {
            apply(payload)
        } else {
            pastDays[dayKey] = .loaded(payload)
        }
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
        let target = dayKey ?? day.value?.dayKey
        guard let target, var payload = payload(for: target) else { return }
        let name = payload.habits.first { $0.habit.id == habitId }?.habit.name ?? "habit"

        payload.habits = payload.habits.map {
            $0.habit.id == habitId ? $0.adjustingReps(by: delta) : $0
        }
        apply(payload, for: target)

        if delta > 0 {
            model?.mutate(
                "POST",
                "/habits/\(habitId)/log",
                // The rep's own id: logging inserts a row, so a replay without
                // this would silently count the habit twice.
                body: HabitLogPayload(dayKey: target, completionId: UUID().uuidString),
                entities: [.habit, .score],
                label: name,
            )
        } else {
            model?.mutate(
                "DELETE",
                "/habits/\(habitId)/log",
                body: HabitLogPayload(dayKey: target, completionId: nil),
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

    /// Sets the feel score for any day the pager can reach — that is the whole
    /// point of being able to swipe back: a day you forgot to rate is still
    /// ratable tomorrow.
    func setMood(_ value: Int, on dayKey: DayKey) {
        guard var payload = payload(for: dayKey) else { return }
        payload.mood = MoodDTO(optimisticValue: value)
        apply(payload, for: dayKey)
        model?.mutate(
            "PUT",
            "/mood/\(dayKey)",
            body: MoodPutRequest(value: value),
            entities: [.mood, .score],
            label: "the feel score for \(DayKeyMath.shortLabel(for: dayKey))",
        )
    }

    static func message(for error: Error) -> String {
        (error as? APIClientError)?.errorDescription ?? "Something went wrong."
    }
}
