import Foundation

// Copy helpers for optimistic UI updates: the app flips the visible state
// instantly, fires the API call in the background, and rolls back to the
// original value if the call fails. DTO fields stay immutable — these build
// modified copies via the package-internal memberwise initializers.

extension TaskDTO {
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
