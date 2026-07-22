import Foundation

// Typed endpoint methods, one section per domain. Create payloads are typed
// structs; PATCH payloads are JSONObject so the app can send explicit nulls
// to clear fields.

// MARK: - Requests

public struct LoginRequest: Encodable, Sendable {
    public let email: String
    public let password: String
    public let deviceName: String?
    public init(email: String, password: String, deviceName: String?) {
        self.email = email
        self.password = password
        self.deviceName = deviceName
    }
}

public struct RegisterRequest: Encodable, Sendable {
    public let email: String
    public let password: String
    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct TaskCreateRequest: Encodable, Sendable {
    public var title: String
    public var notes: String?
    public var dueDate: DayKey?
    public var dueTime: String?
    public var priority: TaskPriority?
    public var goalId: String?
    public var categoryId: String?
    public var parentTaskId: String?

    public init(
        title: String,
        notes: String? = nil,
        dueDate: DayKey? = nil,
        dueTime: String? = nil,
        priority: TaskPriority? = nil,
        goalId: String? = nil,
        categoryId: String? = nil,
        parentTaskId: String? = nil,
    ) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.priority = priority
        self.goalId = goalId
        self.categoryId = categoryId
        self.parentTaskId = parentTaskId
    }
}

public struct TemplateCreateRequest: Encodable, Sendable {
    public var title: String
    public var notes: String?
    public var priority: TaskPriority?
    public var goalId: String?
    public var categoryId: String?
    public var dueTime: String?
    public var rule: RecurrenceRuleDTO
    public var startDate: DayKey
    public var endDate: DayKey?

    public init(
        title: String,
        notes: String? = nil,
        priority: TaskPriority? = nil,
        goalId: String? = nil,
        categoryId: String? = nil,
        dueTime: String? = nil,
        rule: RecurrenceRuleDTO,
        startDate: DayKey,
        endDate: DayKey? = nil,
    ) {
        self.title = title
        self.notes = notes
        self.priority = priority
        self.goalId = goalId
        self.categoryId = categoryId
        self.dueTime = dueTime
        self.rule = rule
        self.startDate = startDate
        self.endDate = endDate
    }
}

public struct TaskCategoryCreateRequest: Encodable, Sendable {
    public let name: String
    public let emoji: String?
    public let colorHex: String?
    public init(name: String, emoji: String? = nil, colorHex: String? = nil) {
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
    }
}

public struct HabitCreateRequest: Encodable, Sendable {
    public var name: String
    public var icon: String?
    public var colorHex: String?
    public var type: HabitType
    public var targetReps: Int?
    public var plannedDays: [Int]?
    public var areaId: String?
    public var goalId: String?
    public var startDate: DayKey?

    public init(
        name: String,
        icon: String? = nil,
        colorHex: String? = nil,
        type: HabitType,
        targetReps: Int? = nil,
        plannedDays: [Int]? = nil,
        areaId: String? = nil,
        goalId: String? = nil,
        startDate: DayKey? = nil,
    ) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.type = type
        self.targetReps = targetReps
        self.plannedDays = plannedDays
        self.areaId = areaId
        self.goalId = goalId
        self.startDate = startDate
    }
}

public struct MoodPutRequest: Encodable, Sendable {
    public let value: Int
    public let note: String?
    public init(value: Int, note: String? = nil) {
        self.value = value
        self.note = note
    }
}

public struct AreaCreateRequest: Encodable, Sendable {
    public let name: String
    public let emoji: String?
    public let colorHex: String?
    public init(name: String, emoji: String? = nil, colorHex: String? = nil) {
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
    }
}

public struct GoalCreateRequest: Encodable, Sendable {
    public let title: String
    public let description: String?
    public let areaId: String?
    public let blockId: String?
    public init(title: String, description: String? = nil, areaId: String? = nil, blockId: String? = nil) {
        self.title = title
        self.description = description
        self.areaId = areaId
        self.blockId = blockId
    }
}

private struct DayKeyBody: Encodable, Sendable {
    let dayKey: DayKey?
}

// MARK: - Endpoints

extension APIClient {
    // Auth
    public func register(email: String, password: String) async throws -> AuthResponse {
        try await post(AuthResponse.self, "/auth/register", body: RegisterRequest(email: email, password: password))
    }

    public func login(email: String, password: String, deviceName: String?) async throws -> AuthResponse {
        try await post(
            AuthResponse.self,
            "/auth/login",
            body: LoginRequest(email: email, password: password, deviceName: deviceName),
        )
    }

    public func logout() async throws -> OkResponse {
        try await post(OkResponse.self, "/auth/logout")
    }

    public func me() async throws -> MeResponse {
        try await get(MeResponse.self, "/auth/me")
    }

    // Settings
    public func settings() async throws -> SettingsDTO {
        try await get(SettingsDTO.self, "/settings")
    }

    public func patchSettings(_ patch: JSONObject) async throws -> SettingsDTO {
        try await self.patch(SettingsDTO.self, "/settings", body: patch)
    }

    // Days & scores
    public func today() async throws -> DayPayload {
        try await get(DayPayload.self, "/days/today")
    }

    public func day(_ dayKey: DayKey) async throws -> DayPayload {
        try await get(DayPayload.self, "/days/\(dayKey)")
    }

    public func scores(from: DayKey, to: DayKey) async throws -> ScoresResponse {
        try await get(
            ScoresResponse.self,
            "/scores",
            query: [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)],
        )
    }

    // Tasks
    public func tasks(view: String? = nil, goalId: String? = nil) async throws -> TaskListResponse {
        var query: [URLQueryItem] = []
        if let view { query.append(URLQueryItem(name: "view", value: view)) }
        if let goalId { query.append(URLQueryItem(name: "goalId", value: goalId)) }
        return try await get(TaskListResponse.self, "/tasks", query: query)
    }

    public func createTask(_ request: TaskCreateRequest) async throws -> TaskDTO {
        try await post(TaskDTO.self, "/tasks", body: request)
    }

    public func patchTask(id: String, _ patch: JSONObject) async throws -> TaskDTO {
        try await self.patch(TaskDTO.self, "/tasks/\(id)", body: patch)
    }

    public func deleteTask(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/tasks/\(id)")
    }

    public func completeTask(id: String) async throws -> TaskDTO {
        try await post(TaskDTO.self, "/tasks/\(id)/complete")
    }

    public func uncompleteTask(id: String) async throws -> TaskDTO {
        try await post(TaskDTO.self, "/tasks/\(id)/uncomplete")
    }

    // Task categories
    public func taskCategories() async throws -> TaskCategoryListResponse {
        try await get(TaskCategoryListResponse.self, "/task-categories")
    }

    public func createTaskCategory(_ request: TaskCategoryCreateRequest) async throws -> TaskCategoryDTO {
        try await post(TaskCategoryDTO.self, "/task-categories", body: request)
    }

    public func patchTaskCategory(id: String, _ patch: JSONObject) async throws -> TaskCategoryDTO {
        try await self.patch(TaskCategoryDTO.self, "/task-categories/\(id)", body: patch)
    }

    public func deleteTaskCategory(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/task-categories/\(id)")
    }

    // Recurrence templates
    public func templates() async throws -> TemplateListResponse {
        try await get(TemplateListResponse.self, "/recurrence-templates")
    }

    public func createTemplate(_ request: TemplateCreateRequest) async throws -> RecurrenceTemplateDTO {
        try await post(RecurrenceTemplateDTO.self, "/recurrence-templates", body: request)
    }

    public func patchTemplate(id: String, _ patch: JSONObject) async throws -> RecurrenceTemplateDTO {
        try await self.patch(RecurrenceTemplateDTO.self, "/recurrence-templates/\(id)", body: patch)
    }

    public func deleteTemplate(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/recurrence-templates/\(id)")
    }

    // Habits
    public func habits(includeArchived: Bool = false) async throws -> HabitListResponse {
        try await get(
            HabitListResponse.self,
            "/habits",
            query: includeArchived ? [URLQueryItem(name: "includeArchived", value: "true")] : [],
        )
    }

    public func createHabit(_ request: HabitCreateRequest) async throws -> HabitDTO {
        try await post(HabitDTO.self, "/habits", body: request)
    }

    public func patchHabit(id: String, _ patch: JSONObject) async throws -> HabitDTO {
        try await self.patch(HabitDTO.self, "/habits/\(id)", body: patch)
    }

    public func archiveHabit(id: String) async throws -> HabitDTO {
        try await post(HabitDTO.self, "/habits/\(id)/archive")
    }

    public func logHabit(id: String, dayKey: DayKey? = nil) async throws -> HabitLogResponse {
        try await post(HabitLogResponse.self, "/habits/\(id)/log", body: DayKeyBody(dayKey: dayKey))
    }

    public func unlogHabit(id: String, dayKey: DayKey? = nil) async throws -> HabitLogResponse {
        try await delete(HabitLogResponse.self, "/habits/\(id)/log", body: DayKeyBody(dayKey: dayKey))
    }

    public func habitCalendar(id: String, month: String) async throws -> HabitCalendarResponse {
        try await get(
            HabitCalendarResponse.self,
            "/habits/\(id)/calendar",
            query: [URLQueryItem(name: "month", value: month)],
        )
    }

    public func habitStats(id: String) async throws -> HabitStatsResponse {
        try await get(HabitStatsResponse.self, "/habits/\(id)/stats")
    }

    // Mood
    public func moods(from: DayKey, to: DayKey) async throws -> MoodListResponse {
        try await get(
            MoodListResponse.self,
            "/mood",
            query: [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)],
        )
    }

    public func putMood(dayKey: DayKey, value: Int, note: String? = nil) async throws -> MoodPutResponse {
        try await put(MoodPutResponse.self, "/mood/\(dayKey)", body: MoodPutRequest(value: value, note: note))
    }

    // Areas
    public func areas() async throws -> AreaListResponse {
        try await get(AreaListResponse.self, "/areas")
    }

    public func createArea(_ request: AreaCreateRequest) async throws -> AreaDTO {
        try await post(AreaDTO.self, "/areas", body: request)
    }

    public func patchArea(id: String, _ patch: JSONObject) async throws -> AreaDTO {
        try await self.patch(AreaDTO.self, "/areas/\(id)", body: patch)
    }

    public func deleteArea(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/areas/\(id)")
    }

    // Goals
    public func goals() async throws -> GoalListResponse {
        try await get(GoalListResponse.self, "/goals")
    }

    public func createGoal(_ request: GoalCreateRequest) async throws -> GoalDTO {
        try await post(GoalDTO.self, "/goals", body: request)
    }

    public func patchGoal(id: String, _ patch: JSONObject) async throws -> GoalDTO {
        try await self.patch(GoalDTO.self, "/goals/\(id)", body: patch)
    }

    public func deleteGoal(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/goals/\(id)")
    }
}
