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
            parentTaskId: parentTaskId,
            templateId: templateId,
            sortOrder: sortOrder,
            subtasks: subtasks,
        )
    }
}

extension HabitTodayEntryDTO {
    /// A copy with reps adjusted by `delta` (today + week totals, floored at
    /// 0 and capped at the daily target for daily/multi-daily habits).
    public func adjustingReps(by delta: Int) -> HabitTodayEntryDTO {
        let dailyCap = habit.type == .weeklyFrequency ? Int.max : habit.targetReps
        let newToday = min(max(repsToday + delta, 0), dailyCap)
        let applied = newToday - repsToday
        return HabitTodayEntryDTO(
            habit: habit,
            repsToday: newToday,
            doneThroughDay: max(doneThroughDay + applied, 0),
            weekTotal: max(weekTotal + applied, 0),
            credit: credit,
            pace: pace,
            plannedToday: plannedToday,
        )
    }
}

extension MoodDTO {
    public init(optimisticValue: Int) {
        self.init(value: optimisticValue, note: nil)
    }
}
