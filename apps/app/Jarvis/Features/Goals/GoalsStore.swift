import Foundation
import JarvisAPI
import Observation

/// Feature store for the Goals tab.
///
/// Local-first like the rest of the app: edits land on screen immediately and
/// go to the offline queue. Every write is idempotent — creates carry a
/// client-generated id, milestone ticks and value logs send absolute state —
/// so a queue replay can never duplicate a goal or double-count progress.
///
/// The server owns `progress`/`timeProgress`; an optimistic edit recomputes
/// them locally with the same formula so the bars move on the tap rather than
/// on the response.
@Observable
@MainActor
final class GoalsStore {
    struct Content: Codable {
        var goals: [GoalDTO]
    }

    private(set) var content: LoadState<Content> = .idle
    var mutationError: String?

    private var model: AppModel?

    var goals: [GoalDTO] { content.value?.goals ?? [] }

    /// Open goals for one horizon, soonest deadline first.
    func active(_ horizon: GoalHorizon) -> [GoalDTO] {
        goals
            .filter { $0.horizon == horizon && $0.status == .active }
            .sorted {
                $0.targetDate == $1.targetDate
                    ? $0.sortOrder < $1.sortOrder
                    : $0.targetDate < $1.targetDate
            }
    }

    /// Goals that have been reached or abandoned — parked below the fold.
    var closed: [GoalDTO] {
        goals.filter { $0.status != .active }.sorted { $0.targetDate > $1.targetDate }
    }

    func goal(_ id: String) -> GoalDTO? {
        goals.first { $0.id == id }
    }

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    func load(force: Bool = false) async {
        guard let model else { return }
        if !force, let cached = model.store.read(Content.self, .goals) {
            content = .loaded(cached.value)
            if cached.isFresh { return }
        }
        if content.value == nil { content = .loading }

        let ticket = model.writeTicket
        do {
            let response = try await model.api.goals(includeClosed: true)
            // A write landed while this was in flight — its response predates
            // the edit on screen, so keep the local state and let the write's
            // own revalidation bring the fresh copy.
            guard !model.hasWritten(since: ticket) else { return }
            apply(Content(goals: response.goals))
            mutationError = nil
        } catch {
            model.handle(error)
            if content.value == nil {
                content = .failed(TodayStore.message(for: error))
            } else {
                mutationError = TodayStore.message(for: error)
            }
        }
    }

    private func apply(_ loaded: Content) {
        content = .loaded(loaded)
        model?.store.write(loaded, .goals)
    }

    /// Replaces one goal and recomputes its derived progress fields.
    private func replace(_ goal: GoalDTO) {
        guard var loaded = content.value else { return }
        loaded.goals = loaded.goals.map { $0.id == goal.id ? goal.recomputed(today: todayKey) : $0 }
        apply(loaded)
    }

    private var todayKey: DayKey {
        DayKeyMath.todayKey(boundaryHour: model?.settings?.dayBoundaryHour ?? 3)
    }

    // MARK: - Mutations

    func create(_ request: GoalCreateRequest) {
        guard let model else { return }
        let id = request.id ?? UUID().uuidString
        var withId = request
        withId.id = id

        if var loaded = content.value {
            loaded.goals.append(
                GoalDTO.locallyCreated(
                    id: id,
                    title: request.title,
                    description: request.description,
                    horizon: request.horizon,
                    areaId: request.areaId,
                    startDate: request.startDate ?? todayKey,
                    targetDate: request.targetDate,
                    unit: request.unit,
                    startValue: request.startValue,
                    targetValue: request.targetValue,
                    currentValue: request.currentValue,
                ).recomputed(today: todayKey),
            )
            apply(loaded)
        }
        model.mutate("POST", "/goals", body: withId, entities: [.goal], label: "\"\(request.title)\"")
    }

    func update(_ goal: GoalDTO, patch: JSONObject, applying edit: (inout GoalDTO) -> Void) {
        var edited = goal
        edit(&edited)
        replace(edited)
        model?.mutate(
            "PATCH",
            "/goals/\(goal.id)",
            body: patch,
            entities: [.goal],
            label: "\"\(goal.title)\"",
        )
    }

    /// Logs where the goal stands now. Absolute, never a delta — a replayed
    /// write lands on the same number.
    func setValue(_ goal: GoalDTO, to value: Double) {
        var edited = goal
        edited.currentValue = value
        replace(edited)
        model?.mutate(
            "PUT",
            "/goals/\(goal.id)/value",
            body: GoalValuePutRequest(currentValue: value),
            entities: [.goal],
            label: "\"\(goal.title)\"",
        )
    }

    func setStatus(_ goal: GoalDTO, to status: GoalStatus) {
        update(goal, patch: ["status": .string(status.rawValue)]) { $0.status = status }
    }

    func delete(_ goal: GoalDTO) {
        if var loaded = content.value {
            loaded.goals.removeAll { $0.id == goal.id }
            apply(loaded)
        }
        model?.mutate("DELETE", "/goals/\(goal.id)", entities: [.goal], label: "\"\(goal.title)\"")
    }

    // MARK: - Milestones

    func addMilestone(to goal: GoalDTO, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = UUID().uuidString
        let sortOrder = (goal.milestones.map(\.sortOrder).max() ?? -1) + 1

        var edited = goal
        edited.milestones.append(
            MilestoneDTO(id: id, goalId: goal.id, title: trimmed, sortOrder: sortOrder),
        )
        replace(edited)

        model?.mutate(
            "POST",
            "/goals/\(goal.id)/milestones",
            body: MilestoneCreateRequest(id: id, title: trimmed, sortOrder: sortOrder),
            entities: [.goal],
            label: "\"\(trimmed)\"",
        )
    }

    /// Ticks or unticks a milestone. The wire format is a boolean, so a replay
    /// re-asserts the same state instead of toggling it back.
    func setMilestone(_ milestone: MilestoneDTO, in goal: GoalDTO, done: Bool) {
        var edited = goal
        edited.milestones = edited.milestones.map {
            guard $0.id == milestone.id else { return $0 }
            var updated = $0
            updated.doneAt = done ? ISO8601DateFormatter().string(from: .now) : nil
            return updated
        }
        replace(edited)

        model?.mutate(
            "PATCH",
            "/milestones/\(milestone.id)",
            body: ["done": JSONValue.bool(done)],
            entities: [.goal],
            label: "\"\(milestone.title)\"",
        )
    }

    func deleteMilestone(_ milestone: MilestoneDTO, in goal: GoalDTO) {
        var edited = goal
        edited.milestones.removeAll { $0.id == milestone.id }
        replace(edited)
        model?.mutate(
            "DELETE",
            "/milestones/\(milestone.id)",
            entities: [.goal],
            label: "\"\(milestone.title)\"",
        )
    }
}

extension GoalDTO {
    /// Recomputes the server-derived progress fields after a local edit, using
    /// the same rules as `apps/api/src/lib/goals.ts` — otherwise an optimistic
    /// tick would move the checkbox but leave the bar behind until the next
    /// fetch.
    func recomputed(today: DayKey) -> GoalDTO {
        var copy = self
        let milestonesDone = milestones.filter(\.isDone).count

        let numeric: Double? = {
            guard let startValue, let targetValue, startValue != targetValue else { return nil }
            let current = currentValue ?? startValue
            return min(max((current - startValue) / (targetValue - startValue), 0), 1)
        }()

        copy.tracking = numeric != nil ? .numeric : (milestones.isEmpty ? .none : .milestones)
        copy.progress = numeric ?? (milestones.isEmpty ? nil : Double(milestonesDone) / Double(milestones.count))
        copy.milestonesDone = milestonesDone
        copy.milestonesTotal = milestones.count

        let daysTotal = max(1, DayKeyMath.diffDays(startDate, targetDate) + 1)
        copy.daysTotal = daysTotal
        copy.timeProgress = min(max(Double(DayKeyMath.diffDays(startDate, today)) / Double(daysTotal), 0), 1)
        copy.daysRemaining = DayKeyMath.diffDays(today, targetDate)
        return copy
    }
}
