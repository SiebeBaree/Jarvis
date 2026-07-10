import Foundation
import JarvisAPI
import Observation

/// Feature store for the Today screen. Fetches the one-shot day payload and
/// exposes mutation helpers. Every successful mutation bumps
/// `model.todayRevision`, which triggers the view's refetch.
@Observable
@MainActor
final class TodayStore {
    private(set) var day: LoadState<DayPayload> = .idle
    /// Inline error from a failed mutation (data on screen stays valid).
    var mutationError: String?
    /// Session-only "Skip" for the yesterday-mood backfill row.
    var backfillSkipped = false

    private var model: AppModel?

    var payload: DayPayload? { day.value }

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    func load() async {
        guard let model else { return }
        if day.value == nil { day = .loading }
        do {
            let payload = try await model.api.today()
            day = .loaded(payload)
        } catch {
            model.handle(error)
            if day.value == nil {
                day = .failed(Self.message(for: error))
            } else {
                mutationError = Self.message(for: error)
            }
        }
    }

    // MARK: - Tasks

    func completeTask(_ task: TaskDTO) async {
        await run { try await $0.completeTask(id: task.id) }
    }

    func uncompleteTask(_ task: TaskDTO) async {
        await run { try await $0.uncompleteTask(id: task.id) }
    }

    func rescheduleTask(_ task: TaskDTO, to dayKey: DayKey) async {
        await run { try await $0.patchTask(id: task.id, ["dueDate": .string(dayKey)]) }
    }

    func createQuickTask(title: String) async {
        guard let payload else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await run { try await $0.createTask(TaskCreateRequest(title: trimmed, dueDate: payload.dayKey)) }
    }

    // MARK: - Habits

    func logHabit(_ habitId: String, dayKey: DayKey? = nil) async {
        await run { try await $0.logHabit(id: habitId, dayKey: dayKey) }
    }

    func unlogHabit(_ habitId: String, dayKey: DayKey? = nil) async {
        await run { try await $0.unlogHabit(id: habitId, dayKey: dayKey) }
    }

    // MARK: - Mood

    func setMood(_ value: Int) async {
        guard let payload else { return }
        await run { try await $0.putMood(dayKey: payload.dayKey, value: value) }
    }

    func setYesterdayMood(_ value: Int) async {
        guard let payload else { return }
        let yesterday = DayKeyMath.addDays(payload.dayKey, -1)
        await run { try await $0.putMood(dayKey: yesterday, value: value) }
    }

    // MARK: - Plumbing

    /// Runs a mutation; on success clears the inline error and invalidates
    /// today so every open screen (including this one) refetches.
    private func run<T: Sendable>(_ operation: (APIClient) async throws -> T) async {
        guard let model else { return }
        do {
            _ = try await operation(model.api)
            mutationError = nil
            model.invalidateToday()
        } catch {
            model.handle(error)
            mutationError = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        (error as? APIClientError)?.errorDescription ?? "Something went wrong."
    }
}
