import Foundation
import Testing
@testable import JarvisAPI

/// Payloads here are copied from live `apps/api` responses, so a server-side
/// shape change fails here rather than silently blanking a screen.
@Suite struct TrainingModelsTests {
    private let decoder = JSONDecoder()

    private let sessionJSON = """
    {"id":"s2","routineId":"r1","title":"Chest & Back","dayKey":"2026-08-18",
     "startedAt":"2026-08-18T12:29:10.211Z","finishedAt":null,"notes":null,
     "exercises":[
       {"exerciseId":"e1","name":"Bench press","muscleGroup":"Chest","equipment":"Barbell",
        "isBodyweight":false,
        "target":{"sets":4,"repsLow":6,"repsHigh":8,"weightKg":80,"restSeconds":null,"notes":null},
        "sets":[{"id":"x1","exerciseId":"e1","setIndex":1,"weightKg":82.5,"reps":8,
                 "isWarmup":false,"completedAt":"2026-08-18T12:29:27.039Z"}],
        "previous":{"sessionId":"s1","dayKey":"2026-08-11","sets":[
          {"id":"p1","exerciseId":"e1","setIndex":1,"weightKg":60,"reps":10,
           "isWarmup":true,"completedAt":"2026-08-11T12:29:08.305Z"},
          {"id":"p2","exerciseId":"e1","setIndex":2,"weightKg":80,"reps":8,
           "isWarmup":false,"completedAt":"2026-08-11T12:29:08.396Z"}]},
        "best":{"weightKg":82.5,"reps":8,"dayKey":"2026-08-18"}},
       {"exerciseId":"e2","name":"Pull-up","muscleGroup":"Back","equipment":null,
        "isBodyweight":true,"target":null,"sets":[],"previous":null,"best":null}
     ],"setCount":1,"volumeKg":660}
    """

    @Test func decodesSessionDetailWithLastTimeAndTargets() throws {
        let session = try decoder.decode(SessionDetailDTO.self, from: Data(sessionJSON.utf8))
        #expect(session.isFinished == false)
        #expect(session.volumeKg == 660)

        let bench = session.exercises[0]
        #expect(bench.target?.repsLabel == "6-8")
        #expect(bench.previous?.dayKey == "2026-08-11")
        // Warm-ups arrive but are not part of the "last time" summary line.
        #expect(bench.previous?.sets.count == 2)
        #expect(bench.previous?.workingSets.count == 1)
        #expect(bench.best?.weightKg == 82.5)
    }

    @Test func decodesAnExerciseWithNoPlanAndNoHistory() throws {
        let session = try decoder.decode(SessionDetailDTO.self, from: Data(sessionJSON.utf8))
        let pullUp = session.exercises[1]
        #expect(pullUp.target == nil)
        #expect(pullUp.previous == nil)
        #expect(pullUp.best == nil)
        #expect(pullUp.isBodyweight)
        #expect(pullUp.isComplete == false)
    }

    @Test func completionCountsWorkingSetsAgainstTheTarget() throws {
        let session = try decoder.decode(SessionDetailDTO.self, from: Data(sessionJSON.utf8))
        // 1 of 4 sets logged.
        #expect(session.exercises[0].isComplete == false)
        #expect(session.exercises[0].workingSets.count == 1)
    }

    @Test func decodesRoutineDetailAndFormatsTargets() throws {
        let json = """
        {"id":"r1","name":"Leg day","emoji":"🦵","colorHex":"#16A34A","notes":null,
         "sortOrder":0,"archived":false,"exercises":[
          {"exerciseId":"e1","name":"Squat","muscleGroup":"Legs","equipment":"Barbell",
           "isBodyweight":false,"targetSets":5,"targetRepsLow":5,"targetRepsHigh":5,
           "targetWeightKg":100,"restSeconds":180,"notes":null,"sortOrder":0},
          {"exerciseId":"e2","name":"Leg curl","muscleGroup":"Legs","equipment":"Machine",
           "isBodyweight":false,"targetSets":3,"targetRepsLow":10,"targetRepsHigh":15,
           "targetWeightKg":null,"restSeconds":null,"notes":null,"sortOrder":1},
          {"exerciseId":"e3","name":"Plank","muscleGroup":"Core","equipment":null,
           "isBodyweight":true,"targetSets":3,"targetRepsLow":null,"targetRepsHigh":null,
           "targetWeightKg":null,"restSeconds":null,"notes":null,"sortOrder":2}]}
        """
        let routine = try decoder.decode(RoutineDetailDTO.self, from: Data(json.utf8))
        // Equal low/high collapses to a single number rather than "5-5".
        #expect(routine.exercises[0].targetLabel == "5 × 5")
        #expect(routine.exercises[1].targetLabel == "3 × 10-15")
        #expect(routine.exercises[2].targetLabel == "3 sets")
    }

    @Test func decodesRoutineListAndSessionHistory() throws {
        let routines = """
        {"routines":[{"id":"r1","name":"Leg day","emoji":"🦵","colorHex":null,"notes":null,
         "sortOrder":0,"archived":false,"exerciseCount":5,"lastPerformedDayKey":"2026-08-11"},
        {"id":"r2","name":"Push","emoji":null,"colorHex":null,"notes":null,"sortOrder":1,
         "archived":false,"exerciseCount":0,"lastPerformedDayKey":null}]}
        """
        let list = try decoder.decode(RoutineListResponse.self, from: Data(routines.utf8))
        #expect(list.routines[0].lastPerformedDayKey == "2026-08-11")
        #expect(list.routines[1].lastPerformedDayKey == nil)

        let sessions = """
        {"sessions":[{"id":"s1","routineId":"r1","title":"Leg day","dayKey":"2026-08-11",
         "startedAt":"2026-08-11T10:00:00.000Z","finishedAt":"2026-08-11T11:05:00.000Z",
         "notes":null,"exerciseCount":5,"setCount":18,"volumeKg":12400.5,"durationMinutes":65}]}
        """
        let history = try decoder.decode(SessionListResponse.self, from: Data(sessions.utf8))
        #expect(history.sessions[0].isFinished)
        #expect(history.sessions[0].durationMinutes == 65)
        #expect(history.sessions[0].volumeKg == 12400.5)
    }

    @Test func decodesProgressionPoints() throws {
        let json = """
        {"exercise":{"id":"e1","name":"Bench press","muscleGroup":"Chest","equipment":"Barbell",
          "isBodyweight":false,"notes":null,"archivedAt":null},
         "points":[
          {"sessionId":"s1","dayKey":"2026-08-11","topWeightKg":80,"topReps":8,
           "estimatedOneRepMax":101.3,"volumeKg":1200,"setCount":2},
          {"sessionId":"s2","dayKey":"2026-08-18","topWeightKg":82.5,"topReps":8,
           "estimatedOneRepMax":104.5,"volumeKg":660,"setCount":1}]}
        """
        let history = try decoder.decode(ExerciseHistoryResponse.self, from: Data(json.utf8))
        #expect(history.exercise.name == "Bench press")
        // Oldest first, so the app can draw it left to right without sorting.
        #expect(history.points.first?.dayKey == "2026-08-11")
        #expect(history.points.last?.estimatedOneRepMax == 104.5)
    }
}
