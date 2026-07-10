import Foundation

// Stage 2 DTOs: vision, blocks, tactics, and the onboarding interview.

// MARK: - Vision

public struct VisionDTO: Codable, Sendable, Equatable {
    public let content: String
    public let updatedAt: String
}

// MARK: - Blocks

public struct BlockDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let number: Int
    public let title: String
    public let startDate: DayKey
    public let endDate: DayKey
    public let status: String // planned | active | completed
}

public struct BlockListResponse: Codable, Sendable {
    public let blocks: [BlockDTO]
}

public struct WeekScoreDTO: Codable, Sendable, Identifiable, Equatable {
    public var id: Int { weekNumber }
    public let weekNumber: Int
    public let avg: Double?
}

public struct TacticDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let goalId: String
    public let title: String
    public let fromWeek: Int
    public let toWeek: Int
    public let sortOrder: Int
    public let completedWeeks: [Int]
}

public struct TacticListResponse: Codable, Sendable {
    public let tactics: [TacticDTO]
}

public struct TacticWeekResponse: Codable, Sendable {
    public let tacticId: String
    public let weekNumber: Int
    public let done: Bool
    public let completedWeeks: [Int]
}

public struct GoalWithProgressDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let blockId: String?
    public let areaId: String?
    public let title: String
    public let description: String?
    public let status: String
    public let trackStatus: String? // on_track | at_risk | done
    public let manualProgress: Int?
    public let sortOrder: Int
    public let areaName: String?
    public let areaEmoji: String?
    public let progress: Double? // 0...1 or null (no tactics yet)
    public let tactics: [TacticDTO]
}

public struct CurrentBlockResponse: Codable, Sendable {
    public let block: BlockDTO?
    public let isUpcoming: Bool
    public let weekNumber: Int?
    public let isReviewWeek: Bool
    public let weekScores: [WeekScoreDTO]
    public let goals: [GoalWithProgressDTO]
}

// MARK: - Interview

public struct InterviewQuestionDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let question: String
    public let type: String // single_choice | multi_choice | free_text | scale
    public let options: [String]?
    public let allowFreeText: Bool
    public let rationale: String?
    public let skippable: Bool
    public let isFollowUp: Bool
}

public struct InterviewProfileDTO: Codable, Sendable, Equatable {
    public var values: [String]
    public var constraints: [String]
    public var schedule: String
    public var motivations: [String]
    public var context: String
}

public struct PlanAreaDTO: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var emoji: String?
}

public struct PlanTacticDTO: Codable, Sendable, Equatable, Hashable {
    public var title: String
    public var fromWeek: Int
    public var toWeek: Int

    public init(title: String, fromWeek: Int, toWeek: Int) {
        self.title = title
        self.fromWeek = fromWeek
        self.toWeek = toWeek
    }
}

public struct PlanHabitDTO: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var icon: String?
    public var type: HabitType
    public var targetReps: Int
    public var plannedDays: [Int]

    public init(name: String, icon: String? = nil, type: HabitType, targetReps: Int, plannedDays: [Int] = []) {
        self.name = name
        self.icon = icon
        self.type = type
        self.targetReps = targetReps
        self.plannedDays = plannedDays
    }
}

public struct PlanTaskDTO: Codable, Sendable, Equatable, Hashable {
    public var title: String
    public var notes: String?
    public var dueOffsetDays: Int?
    public var priority: TaskPriority

    public init(title: String, notes: String? = nil, dueOffsetDays: Int? = nil, priority: TaskPriority) {
        self.title = title
        self.notes = notes
        self.dueOffsetDays = dueOffsetDays
        self.priority = priority
    }
}

public struct PlanGoalDTO: Codable, Sendable, Equatable, Hashable {
    public var title: String
    public var description: String
    public var targetLine: String
    public var areaIndex: Int?
    public var tactics: [PlanTacticDTO]
    public var habits: [PlanHabitDTO]
    public var tasks: [PlanTaskDTO]

    public init(
        title: String,
        description: String = "",
        targetLine: String = "",
        areaIndex: Int? = nil,
        tactics: [PlanTacticDTO] = [],
        habits: [PlanHabitDTO] = [],
        tasks: [PlanTaskDTO] = [],
    ) {
        self.title = title
        self.description = description
        self.targetLine = targetLine
        self.areaIndex = areaIndex
        self.tactics = tactics
        self.habits = habits
        self.tasks = tasks
    }
}

public struct PlanDraftDTO: Codable, Sendable, Equatable {
    public var blockTitle: String
    public var goals: [PlanGoalDTO]
}

public struct InterviewResultDTO: Codable, Sendable, Equatable {
    public var profile: InterviewProfileDTO
    public var visionDraft: String
    public var areas: [PlanAreaDTO]
    public var plan: PlanDraftDTO
}

public struct InterviewRoundDTO: Codable, Sendable, Equatable {
    public let done: Bool
    public let phase: String
    public let phaseIndex: Int
    public let questions: [InterviewQuestionDTO]
    public let result: InterviewResultDTO?
}

public struct InterviewStartResponse: Codable, Sendable {
    public let sessionId: String
    public let round: InterviewRoundDTO
}

public struct ActiveInterviewResponse: Codable, Sendable {
    public let sessionId: String
    public let kind: String
    public let status: String // active | completed
    public let round: InterviewRoundDTO?
    public let result: InterviewResultDTO?
}

public struct InterviewAnswerDTO: Encodable, Sendable {
    public let questionId: String
    public let selectedOptions: [String]
    public let freeText: String?
    public let skipped: Bool

    public init(questionId: String, selectedOptions: [String] = [], freeText: String? = nil, skipped: Bool = false) {
        self.questionId = questionId
        self.selectedOptions = selectedOptions
        self.freeText = freeText
        self.skipped = skipped
    }
}

public struct AnswerRoundResponse: Codable, Sendable {
    public let round: InterviewRoundDTO
}

// MARK: - Apply

public struct ApplyBlockDTO: Codable, Sendable, Equatable {
    public var title: String
    public var startDate: DayKey?

    public init(title: String, startDate: DayKey?) {
        self.title = title
        self.startDate = startDate
    }
}

/// The user-edited payload sent to apply. Mirrors the server's applyPayloadSchema.
public struct ApplyPlanRequest: Encodable, Sendable {
    public var vision: String
    public var profile: InterviewProfileDTO
    public var areas: [PlanAreaDTO]
    public var block: ApplyBlockDTO
    public var goals: [PlanGoalDTO]

    public init(
        vision: String,
        profile: InterviewProfileDTO,
        areas: [PlanAreaDTO],
        block: ApplyBlockDTO,
        goals: [PlanGoalDTO],
    ) {
        self.vision = vision
        self.profile = profile
        self.areas = areas
        self.block = block
        self.goals = goals
    }
}

public struct ApplyPlanResponse: Codable, Sendable {
    public let blockId: String
}
