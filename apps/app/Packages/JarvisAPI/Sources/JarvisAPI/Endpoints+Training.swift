import Foundation

// Workout endpoints: the exercise catalogue, routines, sessions and sets.

public struct ExerciseCreateRequest: Encodable, Sendable {
    public var id: String?
    public var name: String
    public var muscleGroup: String?
    public var equipment: String?
    public var isBodyweight: Bool?

    public init(
        id: String? = nil,
        name: String,
        muscleGroup: String? = nil,
        equipment: String? = nil,
        isBodyweight: Bool? = nil,
    ) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.isBodyweight = isBodyweight
    }
}

/// One line of a routine as sent to the server.
public struct RoutineExerciseInput: Encodable, Sendable, Equatable {
    public var exerciseId: String
    public var targetSets: Int?
    public var targetRepsLow: Int?
    public var targetRepsHigh: Int?
    public var targetWeightKg: Double?
    public var restSeconds: Int?
    public var notes: String?

    public init(
        exerciseId: String,
        targetSets: Int? = nil,
        targetRepsLow: Int? = nil,
        targetRepsHigh: Int? = nil,
        targetWeightKg: Double? = nil,
        restSeconds: Int? = nil,
        notes: String? = nil,
    ) {
        self.exerciseId = exerciseId
        self.targetSets = targetSets
        self.targetRepsLow = targetRepsLow
        self.targetRepsHigh = targetRepsHigh
        self.targetWeightKg = targetWeightKg
        self.restSeconds = restSeconds
        self.notes = notes
    }
}

public struct RoutineCreateRequest: Encodable, Sendable {
    public var id: String?
    public var name: String
    public var emoji: String?
    public var colorHex: String?
    public var notes: String?
    public var sortOrder: Int?
    public var exercises: [RoutineExerciseInput]?

    public init(
        id: String? = nil,
        name: String,
        emoji: String? = nil,
        colorHex: String? = nil,
        notes: String? = nil,
        sortOrder: Int? = nil,
        exercises: [RoutineExerciseInput]? = nil,
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.notes = notes
        self.sortOrder = sortOrder
        self.exercises = exercises
    }
}

public struct RoutinePatchRequest: Encodable, Sendable {
    public var name: String?
    public var emoji: String?
    public var colorHex: String?
    public var notes: String?
    public var exercises: [RoutineExerciseInput]?

    public init(
        name: String? = nil,
        emoji: String? = nil,
        colorHex: String? = nil,
        notes: String? = nil,
        exercises: [RoutineExerciseInput]? = nil,
    ) {
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.notes = notes
        self.exercises = exercises
    }
}

public struct SessionCreateRequest: Encodable, Sendable {
    public var id: String?
    public var routineId: String?
    public var title: String?
    public var dayKey: DayKey?

    public init(id: String? = nil, routineId: String? = nil, title: String? = nil, dayKey: DayKey? = nil) {
        self.id = id
        self.routineId = routineId
        self.title = title
        self.dayKey = dayKey
    }
}

/// Logging one set. `id` is client-generated so a replay through the offline
/// outbox updates the same row instead of adding a phantom set.
public struct SetLogRequest: Encodable, Sendable {
    public var id: String?
    public var exerciseId: String
    public var setIndex: Int?
    public var weightKg: Double?
    public var reps: Int?
    public var isWarmup: Bool?

    public init(
        id: String? = nil,
        exerciseId: String,
        setIndex: Int? = nil,
        weightKg: Double? = nil,
        reps: Int? = nil,
        isWarmup: Bool? = nil,
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
        self.isWarmup = isWarmup
    }
}

extension APIClient {
    // MARK: Exercises

    public func exercises() async throws -> ExerciseListResponse {
        try await get(ExerciseListResponse.self, "/exercises")
    }

    public func createExercise(_ request: ExerciseCreateRequest) async throws -> ExerciseDTO {
        try await post(ExerciseDTO.self, "/exercises", body: request)
    }

    public func patchExercise(id: String, _ patch: JSONObject) async throws -> ExerciseDTO {
        try await self.patch(ExerciseDTO.self, "/exercises/\(id)", body: patch)
    }

    public func deleteExercise(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/exercises/\(id)")
    }

    public func exerciseHistory(id: String, limit: Int? = nil) async throws -> ExerciseHistoryResponse {
        try await get(
            ExerciseHistoryResponse.self,
            "/exercises/\(id)/history",
            query: limit.map { [URLQueryItem(name: "limit", value: String($0))] } ?? [],
        )
    }

    // MARK: Routines

    public func workoutRoutines() async throws -> RoutineListResponse {
        try await get(RoutineListResponse.self, "/workout-routines")
    }

    public func workoutRoutine(id: String) async throws -> RoutineDetailDTO {
        try await get(RoutineDetailDTO.self, "/workout-routines/\(id)")
    }

    public func createRoutine(_ request: RoutineCreateRequest) async throws -> RoutineDetailDTO {
        try await post(RoutineDetailDTO.self, "/workout-routines", body: request)
    }

    public func patchRoutine(id: String, _ request: RoutinePatchRequest) async throws -> RoutineDetailDTO {
        try await patch(RoutineDetailDTO.self, "/workout-routines/\(id)", body: request)
    }

    public func deleteRoutine(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/workout-routines/\(id)")
    }

    // MARK: Sessions

    public func workoutSessions(limit: Int? = nil) async throws -> SessionListResponse {
        try await get(
            SessionListResponse.self,
            "/workout-sessions",
            query: limit.map { [URLQueryItem(name: "limit", value: String($0))] } ?? [],
        )
    }

    public func workoutSession(id: String) async throws -> SessionDetailDTO {
        try await get(SessionDetailDTO.self, "/workout-sessions/\(id)")
    }

    public func startWorkout(_ request: SessionCreateRequest) async throws -> SessionDetailDTO {
        try await post(SessionDetailDTO.self, "/workout-sessions", body: request)
    }

    public func patchWorkout(id: String, _ patch: JSONObject) async throws -> SessionDetailDTO {
        try await self.patch(SessionDetailDTO.self, "/workout-sessions/\(id)", body: patch)
    }

    public func deleteWorkout(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/workout-sessions/\(id)")
    }

    // MARK: Sets

    public func logSet(sessionId: String, _ request: SetLogRequest) async throws -> WorkoutSetDTO {
        try await post(WorkoutSetDTO.self, "/workout-sessions/\(sessionId)/sets", body: request)
    }

    public func patchSet(id: String, _ patch: JSONObject) async throws -> WorkoutSetDTO {
        try await self.patch(WorkoutSetDTO.self, "/workout-sets/\(id)", body: patch)
    }

    public func deleteSet(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/workout-sets/\(id)")
    }
}
