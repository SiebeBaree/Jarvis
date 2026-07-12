import Foundation
import JarvisAPI
import Observation

/// State for the manual setup wizard: the user authors areas, a 12-week
/// block, goals, habits, and improvement areas — the AI plans nothing.
/// Everything is drafted locally and created on the server in one `apply()`
/// pass at the end (retryable as a whole if a call fails).
@Observable
@MainActor
final class SetupWizardStore {
    enum Step: Int, CaseIterable {
        case welcome
        case areas
        case block
        case goals
        case habits
        case improve
        case seed
        case done

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .areas: "Life areas"
            case .block: "Your 12 weeks"
            case .goals: "Goals"
            case .habits: "Habits"
            case .improve: "Improvement areas"
            case .seed: "Meet J.A.R.V.I.S."
            case .done: "Done"
            }
        }
    }

    struct DraftArea: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var emoji: String
    }

    struct DraftGoal: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var description: String = ""
        var areaIndex: Int? // index into `areas`
    }

    struct DraftHabit: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var type: HabitType = .daily
        var targetReps: Int = 1
        var goalIndex: Int? // index into `goals`
    }

    struct DraftImprovementArea: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var emoji: String
        var betterLooksLike: String = ""
    }

    var step: Step = .welcome
    var areas: [DraftArea] = []
    var blockTitle = ""
    var blockStartDate: DayKey = PlanDisplay.nextMonday()
    var goals: [DraftGoal] = []
    var habits: [DraftHabit] = []
    var improvementAreas: [DraftImprovementArea] = []

    private(set) var isApplying = false
    private(set) var applyError: String?
    private(set) var applied = false

    private var model: AppModel?

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    // MARK: - Navigation

    var canGoNext: Bool {
        switch step {
        case .block:
            !blockTitle.trimmingCharacters(in: .whitespaces).isEmpty
        case .goals:
            !goals.isEmpty
        default:
            true
        }
    }

    func next() {
        guard let index = Step.allCases.firstIndex(of: step),
              index + 1 < Step.allCases.count else { return }
        step = Step.allCases[index + 1]
    }

    func back() {
        guard let index = Step.allCases.firstIndex(of: step), index > 0 else { return }
        step = Step.allCases[index - 1]
    }

    /// Steps shown in the progress dots (welcome/done excluded).
    static let progressSteps: [Step] = [.areas, .block, .goals, .habits, .improve, .seed]

    // MARK: - Apply

    /// Creates everything on the server. Runs once, after the habits/improve
    /// steps, before seeding — so the seeding chat sees the real plan.
    func apply() async -> Bool {
        guard let model, !isApplying, !applied else { return applied }
        isApplying = true
        applyError = nil
        do {
            // Life areas → server areas (id per draft index for goal links).
            var areaIds: [Int: String] = [:]
            for (index, area) in areas.enumerated() {
                let name = area.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let created = try await model.api.createArea(AreaCreateRequest(
                    name: name,
                    emoji: area.emoji.isEmpty ? nil : area.emoji,
                ))
                areaIds[index] = created.id
            }

            // The block. The server activates it automatically when no other
            // block is active (rerunning mid-block leaves the current one).
            let block = try await model.api.createBlock(
                title: blockTitle.trimmingCharacters(in: .whitespaces),
                startDate: blockStartDate,
            )

            // Goals, linked to the new block and their area.
            var goalIds: [Int: String] = [:]
            for (index, goal) in goals.enumerated() {
                let title = goal.title.trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                let description = goal.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let created = try await model.api.createGoal(GoalCreateRequest(
                    title: title,
                    description: description.isEmpty ? nil : description,
                    areaId: goal.areaIndex.flatMap { areaIds[$0] },
                    blockId: block.id,
                ))
                goalIds[index] = created.id
            }

            // Habits.
            for habit in habits {
                let name = habit.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                _ = try await model.api.createHabit(HabitCreateRequest(
                    name: name,
                    type: habit.type,
                    targetReps: habit.type == .daily ? nil : habit.targetReps,
                    goalId: habit.goalIndex.flatMap { goalIds[$0] },
                ))
            }

            // Improvement areas.
            for area in improvementAreas {
                let name = area.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let better = area.betterLooksLike.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await model.api.createImprovementArea(ImprovementAreaCreateRequest(
                    name: name,
                    emoji: area.emoji.isEmpty ? nil : area.emoji,
                    betterLooksLike: better.isEmpty ? nil : better,
                ))
            }

            applied = true
            model.invalidateToday()
        } catch {
            model.handle(error)
            applyError = TodayStore.message(for: error)
        }
        isApplying = false
        return applied
    }
}
