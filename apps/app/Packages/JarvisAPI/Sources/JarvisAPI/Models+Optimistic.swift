import Foundation

// Copy helpers for optimistic UI updates: the app flips the visible state
// instantly, fires the API call in the background, and rolls back to the
// original value if the call fails. DTO fields stay immutable — these build
// modified copies via the package-internal memberwise initializers.

extension TaskDTO {
    /// A task created on this device, carrying the client-generated id it
    /// will keep on the server. Lets a new row render instantly and be
    /// completed/edited before the create request has even been sent.
    public static func locallyCreated(
        id: String,
        title: String,
        notes: String? = nil,
        dueDate: DayKey? = nil,
        dueTime: String? = nil,
        priority: TaskPriority = .medium,
        goalId: String? = nil,
        categoryId: String? = nil,
        parentTaskId: String? = nil,
    ) -> TaskDTO {
        TaskDTO(
            id: id,
            title: title,
            notes: notes,
            dueDate: dueDate,
            dueTime: dueTime,
            priority: priority,
            status: .open,
            completedAt: nil,
            goalId: goalId,
            categoryId: categoryId,
            parentTaskId: parentTaskId,
            templateId: nil,
            sortOrder: 0,
            subtasks: [],
        )
    }

    /// A copy with a new status (completedAt set/cleared to match).
    public func with(status: TaskStatus) -> TaskDTO {
        TaskDTO(
            id: id,
            title: title,
            notes: notes,
            dueDate: dueDate,
            dueTime: dueTime,
            priority: priority,
            status: status,
            completedAt: status == .done
                ? ISO8601DateFormatter().string(from: .now)
                : nil,
            goalId: goalId,
            categoryId: categoryId,
            parentTaskId: parentTaskId,
            templateId: templateId,
            sortOrder: sortOrder,
            subtasks: subtasks,
        )
    }

    /// A copy with selected fields replaced, for showing an edit before the
    /// server has confirmed it. The doubly-optional parameters distinguish
    /// "leave unchanged" (`nil`) from "clear this field" (`.some(nil)`).
    public func with(
        title: String? = nil,
        notes: String?? = nil,
        dueDate: DayKey?? = nil,
        dueTime: String?? = nil,
        priority: TaskPriority? = nil,
        goalId: String?? = nil,
        categoryId: String?? = nil,
    ) -> TaskDTO {
        TaskDTO(
            id: id,
            title: title ?? self.title,
            notes: notes ?? self.notes,
            dueDate: dueDate ?? self.dueDate,
            dueTime: dueTime ?? self.dueTime,
            priority: priority ?? self.priority,
            status: status,
            completedAt: completedAt,
            goalId: goalId ?? self.goalId,
            categoryId: categoryId ?? self.categoryId,
            parentTaskId: parentTaskId,
            templateId: templateId,
            sortOrder: sortOrder,
            subtasks: subtasks,
        )
    }

    /// A copy moved to another due date (nil clears it).
    public func with(dueDate newDueDate: DayKey?) -> TaskDTO {
        TaskDTO(
            id: id,
            title: title,
            notes: notes,
            dueDate: newDueDate,
            dueTime: dueTime,
            priority: priority,
            status: status,
            completedAt: completedAt,
            goalId: goalId,
            categoryId: categoryId,
            parentTaskId: parentTaskId,
            templateId: templateId,
            sortOrder: sortOrder,
            subtasks: subtasks,
        )
    }
}

extension TaskRowDTO {
    /// A subtask created on this device, keeping the id it will have on the
    /// server so it can be ticked or deleted before the create is sent.
    public static func locallyCreated(
        id: String,
        title: String,
        dueDate: DayKey?,
        parentTaskId: String,
    ) -> TaskRowDTO {
        TaskRowDTO(
            id: id,
            title: title,
            notes: nil,
            dueDate: dueDate,
            dueTime: nil,
            priority: .medium,
            status: .open,
            completedAt: nil,
            goalId: nil,
            categoryId: nil,
            parentTaskId: parentTaskId,
            templateId: nil,
            sortOrder: 0,
        )
    }

    /// A copy with a new status (completedAt set/cleared to match).
    public func with(status: TaskStatus) -> TaskRowDTO {
        TaskRowDTO(
            id: id,
            title: title,
            notes: notes,
            dueDate: dueDate,
            dueTime: dueTime,
            priority: priority,
            status: status,
            completedAt: status == .done ? ISO8601DateFormatter().string(from: .now) : nil,
            goalId: goalId,
            categoryId: categoryId,
            parentTaskId: parentTaskId,
            templateId: templateId,
            sortOrder: sortOrder,
        )
    }
}

extension HabitTodayEntryDTO {
    /// A copy with today's reps adjusted by `delta` (today + week totals,
    /// floored at 0 and capped at the daily target for daily/multi-daily).
    public func adjustingReps(by delta: Int) -> HabitTodayEntryDTO {
        let dailyCap = habit.type == .weeklyFrequency ? Int.max : habit.targetReps
        let newToday = min(max(repsToday + delta, 0), dailyCap)
        let applied = newToday - repsToday
        guard applied != 0 else { return self }
        let today = recentDays?.last?.dayKey
        return HabitTodayEntryDTO(
            habit: habit,
            repsToday: newToday,
            doneThroughDay: max(doneThroughDay + applied, 0),
            weekTotal: max(weekTotal + applied, 0),
            credit: credit,
            pace: pace,
            plannedToday: plannedToday,
            recentDays: today.map { adjustedRecentDays(by: applied, on: $0) } ?? recentDays,
        )
    }

    /// A copy with reps on a specific past day (from the 7-day strip)
    /// adjusted by `delta`. `countsInWeek` says whether that day falls in the
    /// current score week, so the week total tracks it.
    public func adjustingReps(by delta: Int, on dayKey: DayKey, countsInWeek: Bool) -> HabitTodayEntryDTO {
        let isToday = recentDays?.last?.dayKey == dayKey
        if isToday { return adjustingReps(by: delta) }

        let current = recentDays?.first(where: { $0.dayKey == dayKey })?.reps ?? 0
        let dailyCap = habit.type == .weeklyFrequency ? Int.max : habit.targetReps
        let applied = min(max(current + delta, 0), dailyCap) - current
        guard applied != 0 else { return self }
        return HabitTodayEntryDTO(
            habit: habit,
            repsToday: repsToday,
            doneThroughDay: countsInWeek ? max(doneThroughDay + applied, 0) : doneThroughDay,
            weekTotal: countsInWeek ? max(weekTotal + applied, 0) : weekTotal,
            credit: credit,
            pace: pace,
            plannedToday: plannedToday,
            recentDays: adjustedRecentDays(by: applied, on: dayKey),
        )
    }

    private func adjustedRecentDays(by applied: Int, on dayKey: DayKey) -> [HabitRecentDayDTO]? {
        recentDays?.map {
            $0.dayKey == dayKey ? HabitRecentDayDTO(dayKey: $0.dayKey, reps: max($0.reps + applied, 0)) : $0
        }
    }
}

extension MoodDTO {
    public init(optimisticValue: Int) {
        self.init(value: optimisticValue, note: nil)
    }
}
