import Foundation
import JarvisAPI
import Observation

/// Store backing the Tasks tab: segment state, per-segment fetches, and the
/// task mutations shared by the list and detail screens.
@Observable @MainActor
final class TasksStore {
    enum Segment: String, CaseIterable, Identifiable {
        case today
        case upcoming
        case all
        case done

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .upcoming: "Upcoming"
            case .all: "All"
            case .done: "Done"
            }
        }
    }

    struct TaskGroup: Identifiable {
        let id: String
        let title: String
        let tasks: [TaskDTO]
    }

    private var model: AppModel?

    var segment: Segment = .today {
        didSet {
            guard segment != oldValue else { return }
            Task { await fetch() }
        }
    }

    /// Category filter (TickTick-style pages); nil = all categories.
    var selectedCategoryId: String?
    /// Inline error from a mutation (fetch errors live in `state`).
    var actionError: String?

    private(set) var state: LoadState<[TaskDTO]> = .idle
    /// Open tasks without a due date (view "inbox"), merged into Upcoming.
    private(set) var noDateTasks: [TaskDTO] = []
    private(set) var goals: [GoalDTO] = []
    private(set) var categories: [TaskCategoryDTO] = []
    /// Every task seen in any fetch, so the detail screen can start instantly.
    private(set) var cache: [String: TaskDTO] = [:]

    func bind(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    var todayKey: String {
        DayKeyMath.todayKey(boundaryHour: model?.settings?.dayBoundaryHour ?? 3)
    }

    func goalTitle(for goalId: String?) -> String? {
        guard let goalId else { return nil }
        return goals.first { $0.id == goalId }?.title
    }

    func category(for categoryId: String?) -> TaskCategoryDTO? {
        guard let categoryId else { return nil }
        return categories.first { $0.id == categoryId }
    }

    func task(withId id: String) -> TaskDTO? {
        cache[id]
    }

    // MARK: - Fetching

    private struct SegmentData {
        var tasks: [TaskDTO]
        var noDate: [TaskDTO]
    }

    /// Coalesces callers: `.task`, the segment `didSet`, and the revision
    /// listener can all land together, and each one used to be its own fetch.
    private var inFlight: Task<Void, Never>?

    func fetch(force: Bool = false) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await performFetch(force: force) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performFetch(force: Bool) async {
        guard let model else { return }
        let cacheKey = "tasks:\(segment.rawValue)"
        if !force, let cached: SegmentData = model.cache.get(cacheKey) {
            remember(cached.tasks)
            remember(cached.noDate)
            noDateTasks = cached.noDate
            state = .loaded(cached.tasks)
            return
        }
        if state.value == nil { state = .loading }
        do {
            let data: SegmentData
            switch segment {
            case .today, .all:
                let response = try await model.api.tasks(view: "all")
                data = SegmentData(tasks: response.tasks, noDate: [])
            case .upcoming:
                async let upcomingCall = model.api.tasks(view: "upcoming")
                async let inboxCall = model.api.tasks(view: "inbox")
                let (upcoming, inbox) = try await (upcomingCall, inboxCall)
                data = SegmentData(
                    tasks: upcoming.tasks,
                    noDate: inbox.tasks.filter { $0.status == .open },
                )
            case .done:
                let response = try await model.api.tasks(view: "done")
                data = SegmentData(tasks: response.tasks, noDate: [])
            }
            remember(data.tasks)
            remember(data.noDate)
            noDateTasks = data.noDate
            state = .loaded(data.tasks)
            model.cache.set(cacheKey, data)
        } catch {
            model.handle(error)
            state = .failed(error.localizedDescription)
        }
    }

    func fetchGoals() async {
        guard let model else { return }
        if let cached: [GoalDTO] = model.cache.get("goals") {
            goals = cached
            return
        }
        if let response = try? await model.api.goals() {
            goals = response.goals
            model.cache.set("goals", response.goals)
        }
    }

    func fetchCategories(force: Bool = false) async {
        guard let model else { return }
        if !force, let cached: [TaskCategoryDTO] = model.cache.get("taskCategories") {
            categories = cached
            return
        }
        if let response = try? await model.api.taskCategories() {
            categories = response.categories
            model.cache.set("taskCategories", response.categories)
        }
    }

    // MARK: - Category CRUD

    @discardableResult
    func createCategory(name: String) async -> TaskCategoryDTO? {
        guard let model else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let created = try await model.api.createTaskCategory(
                TaskCategoryCreateRequest(name: trimmed, colorHex: CategoryPalette.next(after: categories.count)),
            )
            actionError = nil
            await fetchCategories(force: true)
            return created
        } catch {
            model.handle(error)
            actionError = error.localizedDescription
            return nil
        }
    }

    func renameCategory(_ category: TaskCategoryDTO, to name: String) async {
        guard let model else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != category.name else { return }
        do {
            _ = try await model.api.patchTaskCategory(id: category.id, ["name": .string(trimmed)])
            actionError = nil
            await fetchCategories(force: true)
        } catch {
            model.handle(error)
            actionError = error.localizedDescription
        }
    }

    /// Deletes the category; its tasks survive with no category.
    func deleteCategory(_ category: TaskCategoryDTO) async {
        guard let model else { return }
        do {
            _ = try await model.api.deleteTaskCategory(id: category.id)
            if selectedCategoryId == category.id { selectedCategoryId = nil }
            actionError = nil
            await fetchCategories(force: true)
            await fetch(force: true)
        } catch {
            model.handle(error)
            actionError = error.localizedDescription
        }
    }

    /// Refetch a single task. This used to pull the whole "all" list (and
    /// then "done") to find one row — the detail screen did it on every open.
    @discardableResult
    func refreshTask(id: String) async -> TaskDTO? {
        guard let model else { return nil }
        do {
            let task = try await model.api.task(id: id)
            remember([task])
            return task
        } catch {
            model.handle(error)
            return nil
        }
    }

    private func remember(_ tasks: [TaskDTO]) {
        for task in tasks {
            cache[task.id] = task
        }
    }

    // MARK: - Derived groups

    private func matchesFilter(_ task: TaskDTO) -> Bool {
        selectedCategoryId == nil || task.categoryId == selectedCategoryId
    }

    private func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }

    private func taskSort(_ a: TaskDTO, _ b: TaskDTO) -> Bool {
        if a.priority != b.priority { return priorityRank(a.priority) < priorityRank(b.priority) }
        if a.dueTime != b.dueTime { return (a.dueTime ?? "~") < (b.dueTime ?? "~") }
        return a.sortOrder < b.sortOrder
    }

    /// Today segment: open tasks past their due date, pinned on top.
    var overdueTasks: [TaskDTO] {
        guard let tasks = state.value else { return [] }
        let today = todayKey
        return tasks
            .filter { $0.status == .open && ($0.dueDate ?? today) < today && matchesFilter($0) }
            .sorted { ($0.dueDate ?? "") != ($1.dueDate ?? "") ? ($0.dueDate ?? "") < ($1.dueDate ?? "") : taskSort($0, $1) }
    }

    /// Today segment: tasks due today (open first, then completed).
    var todayTasks: [TaskDTO] {
        guard let tasks = state.value else { return [] }
        let today = todayKey
        let due = tasks.filter { $0.status != .cancelled && $0.dueDate == today && matchesFilter($0) }
        let open = due.filter { $0.status == .open }.sorted(by: taskSort)
        let done = due.filter { $0.status == .done }.sorted(by: taskSort)
        return open + done
    }

    /// Upcoming segment: "Tomorrow", weekday headers for the next 7 days,
    /// then "Later" and "No date".
    var upcomingGroups: [TaskGroup] {
        guard let tasks = state.value else { return [] }
        let today = todayKey
        let open = tasks.filter { $0.status == .open && matchesFilter($0) }
        var groups: [TaskGroup] = []
        for offset in 1...7 {
            let key = DayKeyMath.addDays(today, offset)
            let dayTasks = open.filter { $0.dueDate == key }.sorted(by: taskSort)
            guard !dayTasks.isEmpty else { continue }
            let title = offset == 1 ? "Tomorrow" : TaskDateLabels.weekdayLabel(for: key)
            groups.append(TaskGroup(id: key, title: title, tasks: dayTasks))
        }
        let horizon = DayKeyMath.addDays(today, 7)
        let later = open
            .filter { ($0.dueDate ?? "") > horizon }
            .sorted { ($0.dueDate ?? "") != ($1.dueDate ?? "") ? ($0.dueDate ?? "") < ($1.dueDate ?? "") : taskSort($0, $1) }
        if !later.isEmpty {
            groups.append(TaskGroup(id: "later", title: "Later", tasks: later))
        }
        let noDate = noDateTasks.filter { matchesFilter($0) }.sorted(by: taskSort)
        if !noDate.isEmpty {
            groups.append(TaskGroup(id: "no-date", title: "No date", tasks: noDate))
        }
        return groups
    }

    /// All segment: everything non-cancelled, by due date with nil last.
    var allTasks: [TaskDTO] {
        guard let tasks = state.value else { return [] }
        return tasks
            .filter { $0.status != .cancelled && matchesFilter($0) }
            .sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (.some(l), .some(r)) where l != r: l < r
                case (.some, .none): true
                case (.none, .some): false
                default: taskSort(a, b)
                }
            }
    }

    /// Done segment: most recently completed first.
    var doneTasks: [TaskDTO] {
        guard let tasks = state.value else { return [] }
        return tasks
            .filter { $0.status == .done && matchesFilter($0) }
            .sorted { ($0.completedAt ?? "") > ($1.completedAt ?? "") }
    }

    // MARK: - Mutations

    /// Optimistic: the row flips instantly, the API call runs behind it, a
    /// failure restores the previous list.
    func toggleComplete(_ task: TaskDTO) async {
        guard let model else { return }
        let originalState = state
        let newStatus: TaskStatus = task.status == .done ? .open : .done
        let optimistic = task.with(status: newStatus)
        if let tasks = state.value {
            state = .loaded(tasks.map { $0.id == task.id ? optimistic : $0 })
        }
        cache[task.id] = optimistic
        do {
            let updated = newStatus == .done
                ? try await model.api.completeTask(id: task.id)
                : try await model.api.uncompleteTask(id: task.id)
            // The optimistic row already matches the server, so no blocking
            // refetch here — invalidateToday() schedules one revalidation for
            // whatever is on screen and drops the cached reads.
            apply(updated)
            actionError = nil
            model.invalidateToday()
        } catch {
            model.handle(error)
            state = originalState
            cache[task.id] = task
            actionError = error.localizedDescription
        }
    }

    /// Optimistic: the row moves to its new day immediately.
    func reschedule(_ task: TaskDTO, to dayKey: String) async {
        guard let model else { return }
        let originalState = state
        let optimistic = task.with(dueDate: dayKey)
        if let tasks = state.value {
            state = .loaded(tasks.map { $0.id == task.id ? optimistic : $0 })
        }
        cache[task.id] = optimistic
        do {
            let updated = try await model.api.patchTask(id: task.id, ["dueDate": .string(dayKey)])
            apply(updated)
            actionError = nil
            model.invalidateToday()
        } catch {
            model.handle(error)
            state = originalState
            cache[task.id] = task
            actionError = error.localizedDescription
        }
    }

    func delete(_ task: TaskDTO) async {
        guard let model else { return }
        let originalState = state
        if let tasks = state.value {
            state = .loaded(tasks.filter { $0.id != task.id })
        }
        do {
            _ = try await model.api.deleteTask(id: task.id)
            cache[task.id] = nil
            actionError = nil
            model.invalidateToday()
        } catch {
            model.handle(error)
            state = originalState
            actionError = error.localizedDescription
        }
    }

    /// Replaces a task in the loaded list and the detail cache with the
    /// server's version of it.
    private func apply(_ task: TaskDTO) {
        cache[task.id] = task
        if let tasks = state.value {
            state = .loaded(tasks.map { $0.id == task.id ? task : $0 })
        }
    }
}

// MARK: - Shared date labels & instant parsing

enum TaskDateLabels {
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let completedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// "Friday Jul 12" for upcoming day headers.
    static func weekdayLabel(for dayKey: String) -> String {
        guard let date = DayKeyMath.date(from: dayKey) else { return dayKey }
        return weekdayFormatter.string(from: date)
    }

    /// "Jul 7" for overdue captions.
    static func shortLabel(for dayKey: String) -> String {
        guard let date = DayKeyMath.date(from: dayKey) else { return dayKey }
        return shortFormatter.string(from: date)
    }

    /// "Jul 9, 22:14" from an ISO-8601 instant string.
    static func completedLabel(for instant: String) -> String? {
        guard let date = InstantParser.date(from: instant) else { return nil }
        return completedFormatter.string(from: date)
    }
}

enum InstantParser {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string)
    }
}
