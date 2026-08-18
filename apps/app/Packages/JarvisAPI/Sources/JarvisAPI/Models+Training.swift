import Foundation

// Workout DTOs. Mirror apps/api 1:1 — weights are kilograms everywhere,
// instants arrive as ISO-8601 strings.

public struct ExerciseDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let muscleGroup: String?
    public let equipment: String?
    public let isBodyweight: Bool
    public let notes: String?
    public let archivedAt: String?

    public init(
        id: String,
        name: String,
        muscleGroup: String? = nil,
        equipment: String? = nil,
        isBodyweight: Bool = false,
        notes: String? = nil,
        archivedAt: String? = nil,
    ) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.isBodyweight = isBodyweight
        self.notes = notes
        self.archivedAt = archivedAt
    }
}

public struct ExerciseListResponse: Codable, Sendable {
    public let exercises: [ExerciseDTO]
}

// MARK: - Routines

/// A routine as it appears in the list: enough to draw the card, no lines.
public struct RoutineSummaryDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let emoji: String?
    public let colorHex: String?
    public let notes: String?
    public let sortOrder: Int
    public let archived: Bool
    public let exerciseCount: Int
    public let lastPerformedDayKey: DayKey?
}

public struct RoutineListResponse: Codable, Sendable {
    public let routines: [RoutineSummaryDTO]
}

/// One line of a routine, with the exercise already resolved.
public struct RoutineExerciseDTO: Codable, Sendable, Identifiable, Equatable {
    public let exerciseId: String
    public let name: String
    public let muscleGroup: String?
    public let equipment: String?
    public let isBodyweight: Bool
    public let targetSets: Int
    public let targetRepsLow: Int?
    public let targetRepsHigh: Int?
    public let targetWeightKg: Double?
    public let restSeconds: Int?
    public let notes: String?
    public let sortOrder: Int

    public var id: String { exerciseId }

    /// "4 × 6-8" / "3 × 10" / "4 sets" — the plan in one glance.
    public var targetLabel: String {
        guard let low = targetRepsLow else { return "\(targetSets) sets" }
        if let high = targetRepsHigh, high != low {
            return "\(targetSets) × \(low)-\(high)"
        }
        return "\(targetSets) × \(low)"
    }
}

public struct RoutineDetailDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let emoji: String?
    public let colorHex: String?
    public let notes: String?
    public let sortOrder: Int
    public let archived: Bool
    public let exercises: [RoutineExerciseDTO]
}

// MARK: - Sessions & sets

public struct WorkoutSetDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let exerciseId: String
    public let setIndex: Int
    public let weightKg: Double?
    public let reps: Int?
    public let isWarmup: Bool
    public let completedAt: String

    public init(
        id: String,
        exerciseId: String,
        setIndex: Int,
        weightKg: Double?,
        reps: Int?,
        isWarmup: Bool,
        completedAt: String,
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }
}

public struct SessionTargetDTO: Codable, Sendable, Equatable {
    public let sets: Int
    public let repsLow: Int?
    public let repsHigh: Int?
    public let weightKg: Double?
    public let restSeconds: Int?
    public let notes: String?

    public var repsLabel: String? {
        guard let low = repsLow else { return nil }
        if let high = repsHigh, high != low { return "\(low)-\(high)" }
        return "\(low)"
    }
}

/// What the same movement looked like the last time it was trained.
public struct PreviousPerformanceDTO: Codable, Sendable, Equatable {
    public let sessionId: String
    public let dayKey: DayKey
    public let sets: [WorkoutSetDTO]

    /// Warm-ups are shown in the detail but never in the one-line summary.
    public var workingSets: [WorkoutSetDTO] { sets.filter { !$0.isWarmup } }
}

public struct PersonalBestDTO: Codable, Sendable, Equatable {
    public let weightKg: Double?
    public let reps: Int?
    public let dayKey: DayKey
}

public struct SessionExerciseDTO: Codable, Sendable, Identifiable, Equatable {
    public let exerciseId: String
    public let name: String
    public let muscleGroup: String?
    public let equipment: String?
    public let isBodyweight: Bool
    public let target: SessionTargetDTO?
    public let sets: [WorkoutSetDTO]
    public let previous: PreviousPerformanceDTO?
    public let best: PersonalBestDTO?

    public var id: String { exerciseId }

    public var workingSets: [WorkoutSetDTO] { sets.filter { !$0.isWarmup } }

    /// True once as many working sets are logged as the routine asked for.
    public var isComplete: Bool {
        guard let target else { return !workingSets.isEmpty }
        return workingSets.count >= target.sets
    }
}

public struct SessionDetailDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let routineId: String?
    public let title: String
    public let dayKey: DayKey
    public let startedAt: String
    public let finishedAt: String?
    public let notes: String?
    public let exercises: [SessionExerciseDTO]
    public let setCount: Int
    public let volumeKg: Double

    public var isFinished: Bool { finishedAt != nil }
}

public struct SessionSummaryDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let routineId: String?
    public let title: String
    public let dayKey: DayKey
    public let startedAt: String
    public let finishedAt: String?
    public let notes: String?
    public let exerciseCount: Int
    public let setCount: Int
    public let volumeKg: Double
    public let durationMinutes: Int?

    public var isFinished: Bool { finishedAt != nil }
}

public struct SessionListResponse: Codable, Sendable {
    public let sessions: [SessionSummaryDTO]
}

// MARK: - Progression

public struct ExerciseHistoryPointDTO: Codable, Sendable, Identifiable, Equatable {
    public let sessionId: String
    public let dayKey: DayKey
    public let topWeightKg: Double?
    public let topReps: Int?
    public let estimatedOneRepMax: Double?
    public let volumeKg: Double
    public let setCount: Int

    public var id: String { sessionId }
}

public struct ExerciseHistoryResponse: Codable, Sendable {
    public let exercise: ExerciseDTO
    public let points: [ExerciseHistoryPointDTO]
}

// MARK: - Optimistic copies
//
// Sets are logged mid-workout, often with no signal. The row has to appear the
// instant the button is tapped, so the app rebuilds the session locally and
// lets the queued request catch up. Fields stay immutable; these build copies.

extension SessionExerciseDTO {
    public func with(sets newSets: [WorkoutSetDTO]) -> SessionExerciseDTO {
        SessionExerciseDTO(
            exerciseId: exerciseId,
            name: name,
            muscleGroup: muscleGroup,
            equipment: equipment,
            isBodyweight: isBodyweight,
            target: target,
            sets: newSets.sorted { $0.setIndex < $1.setIndex },
            previous: previous,
            best: best,
        )
    }
}

extension SessionDetailDTO {
    /// Rebuilds the session around a changed exercise list, recomputing the
    /// two totals so the header never disagrees with the rows under it.
    public func with(exercises newExercises: [SessionExerciseDTO]) -> SessionDetailDTO {
        let allSets = newExercises.flatMap(\.sets)
        let working = allSets.filter { !$0.isWarmup }
        let volume = working.reduce(0.0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
        return SessionDetailDTO(
            id: id,
            routineId: routineId,
            title: title,
            dayKey: dayKey,
            startedAt: startedAt,
            finishedAt: finishedAt,
            notes: notes,
            exercises: newExercises,
            setCount: working.count,
            volumeKg: (volume * 10).rounded() / 10,
        )
    }

    public func with(finishedAt newFinishedAt: String?) -> SessionDetailDTO {
        SessionDetailDTO(
            id: id,
            routineId: routineId,
            title: title,
            dayKey: dayKey,
            startedAt: startedAt,
            finishedAt: newFinishedAt,
            notes: notes,
            exercises: exercises,
            setCount: setCount,
            volumeKg: volumeKg,
        )
    }

    /// Appends an exercise that is not in the routine — added at the rack.
    public func adding(exercise: ExerciseDTO) -> SessionDetailDTO {
        guard !exercises.contains(where: { $0.exerciseId == exercise.id }) else { return self }
        return with(exercises: exercises + [
            SessionExerciseDTO(
                exerciseId: exercise.id,
                name: exercise.name,
                muscleGroup: exercise.muscleGroup,
                equipment: exercise.equipment,
                isBodyweight: exercise.isBodyweight,
                target: nil,
                sets: [],
                previous: nil,
                best: nil,
            ),
        ])
    }
}
