import Foundation
import JarvisAPI
import Observation

/// The workout tracker's state: routines, the exercise catalogue, the session
/// history, and whichever workout is currently open.
///
/// Set logging is the one write here that has to be instant and offline-safe.
/// A gym is the worst network environment the app will ever see, so a logged
/// set is applied locally, written to the per-session cache (so it survives a
/// relaunch) and queued — it never waits on a response, and a replayed request
/// updates the same row because the set carries a client-generated id.
@Observable
@MainActor
final class WorkoutsStore {
    private(set) var routines: LoadState<[RoutineSummaryDTO]> = .idle
    private(set) var sessions: LoadState<[SessionSummaryDTO]> = .idle
    private(set) var exercises: [ExerciseDTO] = []
    /// Session details by id, so reopening a workout paints immediately.
    private(set) var details: [String: SessionDetailDTO] = [:]
    var actionError: String?

    private var model: AppModel?

    func bind(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    var routineList: [RoutineSummaryDTO] { routines.value ?? [] }
    var sessionList: [SessionSummaryDTO] { sessions.value ?? [] }

    /// The workout that is still open, if any. Drives the "Continue" card —
    /// forgetting to press Finish is the normal case, not the exception.
    var activeSession: SessionSummaryDTO? {
        sessionList.first { !$0.isFinished }
    }

    func detail(_ id: String) -> SessionDetailDTO? { details[id] }

    // MARK: - Loading

    func loadAll(force: Bool = false) async {
        async let routinesTask: Void = loadRoutines(force: force)
        async let sessionsTask: Void = loadSessions(force: force)
        async let exercisesTask: Void = loadExercises(force: force)
        _ = await (routinesTask, sessionsTask, exercisesTask)
    }

    func loadRoutines(force: Bool = false) async {
        guard let model else { return }
        if !force, let cached = model.store.read([RoutineSummaryDTO].self, .routines) {
            routines = .loaded(cached.value)
            if cached.isFresh { return }
        }
        if routines.value == nil { routines = .loading }
        do {
            let response = try await model.api.workoutRoutines()
            routines = .loaded(response.routines)
            model.store.write(response.routines, .routines)
        } catch {
            model.handle(error)
            if routines.value == nil { routines = .failed(TodayStore.message(for: error)) }
        }
    }

    func loadSessions(force: Bool = false) async {
        guard let model else { return }
        if !force, let cached = model.store.read([SessionSummaryDTO].self, .workoutSessions) {
            sessions = .loaded(cached.value)
            if cached.isFresh { return }
        }
        if sessions.value == nil { sessions = .loading }
        let ticket = model.writeTicket
        do {
            let response = try await model.api.workoutSessions(limit: 60)
            guard !model.hasWritten(since: ticket) else { return }
            sessions = .loaded(response.sessions)
            model.store.write(response.sessions, .workoutSessions)
        } catch {
            model.handle(error)
            if sessions.value == nil { sessions = .failed(TodayStore.message(for: error)) }
        }
    }

    func loadExercises(force: Bool = false) async {
        guard let model else { return }
        if !force, let cached = model.store.read([ExerciseDTO].self, .exercises) {
            exercises = cached.value
            if cached.isFresh { return }
        }
        guard let response = try? await model.api.exercises() else { return }
        exercises = response.exercises
        model.store.write(response.exercises, .exercises)
    }

    /// Loads one workout. Paints from cache first — at the gym the cached copy
    /// is usually the only copy that exists.
    func loadDetail(_ id: String, force: Bool = false) async {
        guard let model else { return }
        if details[id] == nil,
           let cached = model.store.read(SessionDetailDTO.self, .workoutSession(id: id)) {
            details[id] = cached.value
        }
        let ticket = model.writeTicket
        do {
            let detail = try await model.api.workoutSession(id: id)
            // A set logged while this was in flight is newer than the answer.
            guard !model.hasWritten(since: ticket) else { return }
            apply(detail)
        } catch {
            model.handle(error)
            if details[id] == nil { actionError = TodayStore.message(for: error) }
        }
        _ = force
    }

    private func apply(_ detail: SessionDetailDTO) {
        details[detail.id] = detail
        model?.store.write(detail, .workoutSession(id: detail.id))
    }

    // MARK: - Sessions

    /// Starts a workout from a routine (or freeform) and returns its id.
    /// Awaited rather than queued: the plan and the "last time" numbers are
    /// what makes the screen worth opening, and they only come from the server.
    func startWorkout(routineId: String?, title: String?) async -> String? {
        guard let model else { return nil }
        do {
            let detail = try await model.api.startWorkout(
                SessionCreateRequest(id: UUID().uuidString, routineId: routineId, title: title),
            )
            apply(detail)
            await loadSessions(force: true)
            model.invalidate([.workout])
            return detail.id
        } catch {
            model.handle(error)
            actionError = TodayStore.message(for: error)
            return nil
        }
    }

    func finishWorkout(_ id: String) {
        guard let model, let detail = details[id] else { return }
        apply(detail.with(finishedAt: ISO8601DateFormatter().string(from: .now)))
        model.mutate(
            "PATCH",
            "/workout-sessions/\(id)",
            body: ["finished": JSONValue.bool(true)] as JSONObject,
            entities: [.workout],
            label: detail.title,
        )
    }

    func reopenWorkout(_ id: String) {
        guard let model, let detail = details[id] else { return }
        apply(detail.with(finishedAt: nil))
        model.mutate(
            "PATCH",
            "/workout-sessions/\(id)",
            body: ["finished": JSONValue.bool(false)] as JSONObject,
            entities: [.workout],
            label: detail.title,
        )
    }

    func deleteWorkout(_ id: String) {
        guard let model else { return }
        let title = details[id]?.title ?? sessionList.first { $0.id == id }?.title ?? "workout"
        details[id] = nil
        sessions = .loaded(sessionList.filter { $0.id != id })
        model.store.write(sessionList, .workoutSessions)
        model.mutate("DELETE", "/workout-sessions/\(id)", entities: [.workout], label: title)
    }

    // MARK: - Sets

    /// Logs one set. Appears instantly, queued for the server.
    func logSet(sessionId: String, exerciseId: String, weightKg: Double?, reps: Int?, isWarmup: Bool) {
        guard let model, let detail = details[sessionId] else { return }
        guard let exercise = detail.exercises.first(where: { $0.exerciseId == exerciseId }) else { return }

        let setId = UUID().uuidString
        let nextIndex = (exercise.sets.map(\.setIndex).max() ?? 0) + 1
        let set = WorkoutSetDTO(
            id: setId,
            exerciseId: exerciseId,
            setIndex: nextIndex,
            weightKg: weightKg,
            reps: reps,
            isWarmup: isWarmup,
            completedAt: ISO8601DateFormatter().string(from: .now),
        )
        apply(detail.with(exercises: detail.exercises.map { entry in
            entry.exerciseId == exerciseId ? entry.with(sets: entry.sets + [set]) : entry
        }))

        model.mutate(
            "POST",
            "/workout-sessions/\(sessionId)/sets",
            body: SetLogRequest(
                id: setId,
                exerciseId: exerciseId,
                // Sent explicitly: the server would otherwise recompute it, and
                // a replay after a partial failure could shift the numbering.
                setIndex: nextIndex,
                weightKg: weightKg,
                reps: reps,
                isWarmup: isWarmup,
            ),
            entities: [.workout],
            label: "\(exercise.name) set \(nextIndex)",
        )
    }

    func updateSet(sessionId: String, set: WorkoutSetDTO, weightKg: Double?, reps: Int?, isWarmup: Bool) {
        guard let model, let detail = details[sessionId] else { return }
        let updated = WorkoutSetDTO(
            id: set.id,
            exerciseId: set.exerciseId,
            setIndex: set.setIndex,
            weightKg: weightKg,
            reps: reps,
            isWarmup: isWarmup,
            completedAt: set.completedAt,
        )
        apply(detail.with(exercises: detail.exercises.map { entry in
            guard entry.exerciseId == set.exerciseId else { return entry }
            return entry.with(sets: entry.sets.map { $0.id == set.id ? updated : $0 })
        }))

        model.mutate(
            "PATCH",
            "/workout-sets/\(set.id)",
            body: [
                "weightKg": weightKg.map(JSONValue.double) ?? .null,
                "reps": reps.map(JSONValue.int) ?? .null,
                "isWarmup": JSONValue.bool(isWarmup),
            ] as JSONObject,
            entities: [.workout],
            label: "set \(set.setIndex)",
        )
    }

    func deleteSet(sessionId: String, set: WorkoutSetDTO) {
        guard let model, let detail = details[sessionId] else { return }
        apply(detail.with(exercises: detail.exercises.map { entry in
            guard entry.exerciseId == set.exerciseId else { return entry }
            return entry.with(sets: entry.sets.filter { $0.id != set.id })
        }))
        model.mutate(
            "DELETE",
            "/workout-sets/\(set.id)",
            entities: [.workout],
            label: "set \(set.setIndex)",
        )
    }

    /// Adds a movement that is not in the routine — the "the rack was taken,
    /// I did dumbbells instead" case.
    func addExercise(_ exercise: ExerciseDTO, to sessionId: String) {
        guard let detail = details[sessionId] else { return }
        apply(detail.adding(exercise: exercise))
    }

    // MARK: - Exercises

    /// Creates an exercise, or hands back the existing one with that name —
    /// the server treats a duplicate name as a reuse so history stays in one
    /// place rather than splitting across two near-identical rows.
    func createExercise(name: String, muscleGroup: String?, isBodyweight: Bool) async -> ExerciseDTO? {
        guard let model else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = exercises.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        do {
            let created = try await model.api.createExercise(
                ExerciseCreateRequest(
                    name: trimmed,
                    muscleGroup: muscleGroup,
                    isBodyweight: isBodyweight,
                ),
            )
            if !exercises.contains(where: { $0.id == created.id }) {
                exercises.append(created)
                exercises.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            model.store.write(exercises, .exercises)
            model.invalidate([.exercise])
            return created
        } catch {
            model.handle(error)
            actionError = TodayStore.message(for: error)
            return nil
        }
    }

    // MARK: - Routines

    func routineDetail(_ id: String) async -> RoutineDetailDTO? {
        guard let model else { return nil }
        do {
            return try await model.api.workoutRoutine(id: id)
        } catch {
            model.handle(error)
            actionError = TodayStore.message(for: error)
            return nil
        }
    }

    func saveRoutine(
        id: String?,
        name: String,
        emoji: String?,
        colorHex: String?,
        exercises lines: [RoutineExerciseInput],
    ) async -> Bool {
        guard let model else { return false }
        do {
            if let id {
                _ = try await model.api.patchRoutine(
                    id: id,
                    RoutinePatchRequest(name: name, emoji: emoji, colorHex: colorHex, exercises: lines),
                )
            } else {
                _ = try await model.api.createRoutine(
                    RoutineCreateRequest(
                        id: UUID().uuidString,
                        name: name,
                        emoji: emoji,
                        colorHex: colorHex,
                        sortOrder: routineList.count,
                        exercises: lines,
                    ),
                )
            }
            await loadRoutines(force: true)
            model.invalidate([.routine])
            return true
        } catch {
            model.handle(error)
            actionError = TodayStore.message(for: error)
            return false
        }
    }

    func deleteRoutine(_ id: String) async {
        guard let model else { return }
        do {
            _ = try await model.api.deleteRoutine(id: id)
            routines = .loaded(routineList.filter { $0.id != id })
            model.store.write(routineList, .routines)
            model.invalidate([.routine])
        } catch {
            model.handle(error)
            actionError = TodayStore.message(for: error)
        }
    }

    // MARK: - Progress summary

    /// Sessions and volume over the last `weeks` weeks, oldest first, for the
    /// bars on the Train home. Built from the session list the screen already
    /// has, so the overview costs no extra request.
    struct WeekBar: Identifiable {
        let weekStart: DayKey
        let sessions: Int
        let volumeKg: Double
        var id: DayKey { weekStart }
    }

    func weeklyBars(weeks: Int = 8) -> [WeekBar] {
        let today = DayKeyMath.todayKey(boundaryHour: model?.settings?.dayBoundaryHour ?? 3)
        let currentWeekStart = HabitDisplay.weekStart(of: today)

        let starts: [DayKey] = (0..<weeks)
            .reversed()
            .map { DayKeyMath.addDays(currentWeekStart, -7 * $0) }

        return starts.map { start in
            let end = DayKeyMath.addDays(start, 6)
            let inWeek = sessionList.filter { $0.dayKey >= start && $0.dayKey <= end }
            return WeekBar(
                weekStart: start,
                sessions: inWeek.count,
                volumeKg: inWeek.reduce(0) { $0 + $1.volumeKg },
            )
        }
    }
}
