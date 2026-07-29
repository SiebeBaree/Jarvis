import Foundation

// DTOs mirror apps/api JSON responses 1:1 (camelCase keys, dayKeys as
// YYYY-MM-DD strings, instants as ISO-8601 strings with fractional seconds).

public typealias DayKey = String

// MARK: - Auth & settings

public struct UserDTO: Codable, Sendable, Equatable {
    public let id: String
    public let email: String
}

public struct AuthResponse: Codable, Sendable {
    public let token: String
    public let user: UserDTO
}

public struct ScoreWeights: Codable, Sendable, Equatable {
    public let tasks: Double
    public let habits: Double
    public let feel: Double
}

public struct SettingsDTO: Codable, Sendable, Equatable {
    public let timezone: String
    public let dayBoundaryHour: Int
    public let weekStartsOn: Int
    public let scoreWeights: ScoreWeights
    public let moodScaleMax: Int
}

public struct MeResponse: Codable, Sendable {
    public let user: UserDTO
    public let settings: SettingsDTO
}

// MARK: - Tasks

public enum TaskPriority: String, Codable, Sendable, CaseIterable {
    case low, medium, high
}

public enum TaskStatus: String, Codable, Sendable {
    case open, done, cancelled
}

public struct TaskRowDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let notes: String?
    public let dueDate: DayKey?
    public let dueTime: String?
    public let priority: TaskPriority
    public let status: TaskStatus
    public let completedAt: String?
    /// Optional so payloads from servers predating categories decode.
    public let categoryId: String?
    public let parentTaskId: String?
    public let templateId: String?
    public let sortOrder: Int
}

public struct TaskDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let notes: String?
    public let dueDate: DayKey?
    public let dueTime: String?
    public let priority: TaskPriority
    public let status: TaskStatus
    public let completedAt: String?
    /// Optional so payloads from servers predating categories decode.
    public let categoryId: String?
    public let parentTaskId: String?
    public let templateId: String?
    public let sortOrder: Int
    public var subtasks: [TaskRowDTO]
}

public struct TaskListResponse: Codable, Sendable {
    public let tasks: [TaskDTO]
}

// MARK: - Task categories

/// TickTick-style task list/category — purely organizational.
public struct TaskCategoryDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let emoji: String?
    public let colorHex: String?
    public let sortOrder: Int
    public let archivedAt: String?
}

public struct TaskCategoryListResponse: Codable, Sendable {
    public let categories: [TaskCategoryDTO]
}

// MARK: - Recurrence templates

public struct RecurrenceRuleDTO: Codable, Sendable, Equatable {
    public var freq: String // daily | weekly | monthly
    public var interval: Int
    public var byWeekday: [Int]?
    public var byMonthDay: Int?

    public init(freq: String, interval: Int, byWeekday: [Int]? = nil, byMonthDay: Int? = nil) {
        self.freq = freq
        self.interval = interval
        self.byWeekday = byWeekday
        self.byMonthDay = byMonthDay
    }
}

public struct RecurrenceTemplateDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let notes: String?
    public let priority: TaskPriority
    /// Optional so payloads from servers predating categories decode.
    public let categoryId: String?
    public let dueTime: String?
    public let rule: RecurrenceRuleDTO
    public let startDate: DayKey
    public let endDate: DayKey?
    public let pausedAt: String?
}

public struct TemplateListResponse: Codable, Sendable {
    public let templates: [RecurrenceTemplateDTO]
}

// MARK: - Habits

public enum HabitType: String, Codable, Sendable, CaseIterable {
    case daily
    case multiDaily = "multi_daily"
    case weeklyFrequency = "weekly_frequency"
}

public struct HabitDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let icon: String?
    public let colorHex: String?
    public let type: HabitType
    public let targetReps: Int
    public let plannedDays: [Int]
    public let areaId: String?
    public let startDate: DayKey
    public let pausedAt: String?
    public let archivedAt: String?
    public let sortOrder: Int
}

public struct HabitListResponse: Codable, Sendable {
    public let habits: [HabitDTO]
}

public struct PaceDTO: Codable, Sendable, Equatable {
    public let kind: String // week_done | on_pace | behind | out_of_reach
    public let by: Int?
}

/// One day of the trailing-7-day backfill strip.
public struct HabitRecentDayDTO: Codable, Sendable, Identifiable, Equatable {
    public var id: String { dayKey }
    public let dayKey: DayKey
    public let reps: Int

    public init(dayKey: DayKey, reps: Int) {
        self.dayKey = dayKey
        self.reps = reps
    }
}

public struct HabitTodayEntryDTO: Codable, Sendable, Identifiable, Equatable {
    public var id: String { habit.id }
    public let habit: HabitDTO
    public let repsToday: Int
    public let doneThroughDay: Int
    public let weekTotal: Int
    public let credit: Double
    public let pace: PaceDTO?
    public let plannedToday: Bool
    /// Reps for the trailing 7 days (oldest first, ending today). Optional so
    /// payloads from servers predating the field decode.
    public let recentDays: [HabitRecentDayDTO]?
}

public struct HabitLogResponse: Codable, Sendable {
    public let repsToday: Int
    public let weekTotal: Int
    public let credit: Double
}

public struct CalendarDayDTO: Codable, Sendable, Identifiable, Equatable {
    public var id: String { dayKey }
    public let dayKey: DayKey
    public let reps: Int
    public let target: Int
    public let credit: Double?
    public let state: String // full | partial | none | not_applicable
}

public struct CalendarWeekDTO: Codable, Sendable, Identifiable, Equatable {
    public var id: String { weekStart }
    public let weekStart: DayKey
    public let total: Int
    public let target: Int
    public let result: String // met | missed | live
}

public struct HabitCalendarResponse: Codable, Sendable {
    public let days: [CalendarDayDTO]
    public let weeks: [CalendarWeekDTO]?
}

public struct StreakDTO: Codable, Sendable, Equatable {
    public let current: Int
    public let best: Int
    public let unit: String // days | weeks
}

public struct CurrentWeekDTO: Codable, Sendable, Equatable {
    public let total: Int
    public let target: Int
}

public struct HabitStatsResponse: Codable, Sendable {
    public let type: HabitType
    public let streak: StreakDTO
    // Values are nullable server-side (insufficient history → null).
    public let rates: [String: Double?]
    public let totalReps: Int
    public let currentWeek: CurrentWeekDTO?
}

// MARK: - Score / day payload

public struct BreakdownTaskDTO: Codable, Sendable, Equatable {
    public let taskId: String
    public let credit: Double
    public let late: Bool
}

public struct BreakdownHabitDTO: Codable, Sendable, Equatable {
    public let habitId: String
    public let credit: Double
    public let reps: Double
    public let expected: Double
    public let reconciled: Bool
}

public struct ScoreBreakdownDTO: Codable, Sendable, Equatable {
    public let tasks: [BreakdownTaskDTO]
    public let habits: [BreakdownHabitDTO]
}

public struct DaySnapshotDTO: Codable, Sendable, Equatable {
    public let dayKey: DayKey
    public let total: Double?
    public let taskPoints: Double?
    public let habitPoints: Double?
    public let feelPoints: Double?
    public let applicableWeight: Double
    public let isFinal: Bool
    public let breakdown: ScoreBreakdownDTO
}

public struct MoodDTO: Codable, Sendable, Equatable {
    public let value: Int
    public let note: String?
}

/// One day's worth of everything Today renders. The same shape serves today
/// and the three days behind it, so the day pager has nothing special to do.
public struct DayPayload: Codable, Sendable {
    public let dayKey: DayKey
    public let score: DaySnapshotDTO
    public var tasksDue: [TaskDTO]
    /// Only populated for today — a past day's overdue list isn't actionable.
    public var overdueTasks: [TaskDTO]
    public var habits: [HabitTodayEntryDTO]
    public var mood: MoodDTO?
}

public struct ScorePointDTO: Codable, Sendable, Identifiable, Equatable {
    public var id: String { dayKey }
    public let dayKey: DayKey
    public let total: Double?
    public let taskPoints: Double?
    public let habitPoints: Double?
    public let feelPoints: Double?
    public let isFinal: Bool
}

public struct ScoresResponse: Codable, Sendable {
    public let scores: [ScorePointDTO]
}

public struct MoodEntryDTO: Codable, Sendable, Identifiable, Equatable {
    public var id: String { dayKey }
    public let dayKey: DayKey
    public let value: Int
    public let note: String?
}

public struct MoodListResponse: Codable, Sendable {
    public let moods: [MoodEntryDTO]
}

public struct MoodPutResponse: Codable, Sendable {
    public let mood: MoodEntryDTO
    public let score: DaySnapshotDTO
}

// MARK: - Areas & goals

public struct AreaDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let emoji: String?
    public let colorHex: String?
    public let sortOrder: Int
    public let archivedAt: String?
}

public struct AreaListResponse: Codable, Sendable {
    public let areas: [AreaDTO]
}

// MARK: - Goals

public enum GoalHorizon: String, Codable, Sendable, CaseIterable, Identifiable {
    case short, long

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .short: "Short term"
        case .long: "Long term"
        }
    }
}

public enum GoalStatus: String, Codable, Sendable, CaseIterable {
    case active, achieved, dropped
}

/// How a goal's completion is measured. Mirrors the server's decision so the
/// client never has to re-derive it.
public enum GoalTracking: String, Codable, Sendable {
    case numeric, milestones, none
}

public struct MilestoneDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let goalId: String
    public var title: String
    public var doneAt: String?
    public var sortOrder: Int

    public var isDone: Bool { doneAt != nil }

    public init(id: String, goalId: String, title: String, doneAt: String? = nil, sortOrder: Int = 0) {
        self.id = id
        self.goalId = goalId
        self.title = title
        self.doneAt = doneAt
        self.sortOrder = sortOrder
    }
}

public struct GoalDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let areaId: String?
    public var title: String
    public var description: String?
    public var horizon: GoalHorizon
    public var status: GoalStatus
    public var startDate: DayKey
    public var targetDate: DayKey
    public var unit: String?
    public var startValue: Double?
    public var targetValue: Double?
    public var currentValue: Double?
    public var sortOrder: Int
    public var milestones: [MilestoneDTO]

    // Server-computed, so the two bars always agree with the stored numbers.
    // Defaulted so a locally created goal can be built without restating
    // them; `recomputed(today:)` fills them in with the server's formula.
    public var tracking: GoalTracking = .none
    /// 0...1, or nil when the goal has neither a numeric target nor milestones.
    public var progress: Double?
    /// 0...1, clamped — a goal past its date sits at 1.
    public var timeProgress: Double = 0
    public var daysTotal: Int = 1
    /// Negative once the target date has passed.
    public var daysRemaining: Int = 0
    public var milestonesDone: Int = 0
    public var milestonesTotal: Int = 0
}

public struct GoalListResponse: Codable, Sendable {
    public let goals: [GoalDTO]
}

public struct OkResponse: Codable, Sendable {
    public let ok: Bool
}
