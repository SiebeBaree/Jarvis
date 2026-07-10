import Foundation
import JarvisAPI
import Observation

/// State machine for the onboarding interview flow (§B6):
/// probing → landing / answering → thinking → … → reviewing → applying → done.
@Observable
@MainActor
final class OnboardingStore {
    enum Phase: Equatable {
        /// Checking for a resumable draft via `interviewActive`.
        case probing
        case probeFailed(String)
        /// No draft — intro card with "Begin".
        case landing
        /// A round is on screen waiting for answers.
        case answering
        /// Answers are in flight (30–120 s server-side).
        case thinking
        /// Interview complete — Plan Proposal Review.
        case reviewing
        case applying
        /// Plan applied; the flow should dismiss.
        case done
    }

    /// One dimmed scroll-back row above the active card.
    struct TranscriptEntry: Identifiable {
        enum Kind {
            case phaseDivider(String)
            case qa(question: String, answer: String, isFollowUp: Bool)
        }

        let id = UUID()
        let kind: Kind
    }

    /// Per-question in-progress answer for the current round.
    struct AnswerDraft {
        var selected: [String] = []
        var freeText: String = ""
        /// Whether the "✎ Write my own" row is expanded.
        var freeTextActive = false
        var skipped = false
    }

    /// The 6 named phases from §B6 — never a percentage.
    static let phaseNames = [
        "About you", "Life areas", "Your vision",
        "This block's goals", "Habits & routines", "Wrap-up",
    ]

    let forceFresh: Bool
    /// Interview kind sent to the server ("onboarding" or "reonboarding").
    let kind: String

    private(set) var phase: Phase
    private(set) var sessionId: String?
    private(set) var round: InterviewRoundDTO?
    /// Mutable plan draft the review screen edits in place.
    var result: InterviewResultDTO?
    private(set) var transcript: [TranscriptEntry] = []
    var drafts: [String: AnswerDraft] = [:]

    /// Error while an answer round was in flight (shown in the thinking card).
    private(set) var answerError: String?
    /// Error from `interviewStart` (shown on the landing card).
    private(set) var startError: String?
    /// Error from `interviewApply` (alert on the review screen).
    var applyError: String?
    private(set) var isStarting = false

    private var pendingAnswers: [InterviewAnswerDTO] = []
    private var model: AppModel?

    init(forceFresh: Bool = false, kind: String = "onboarding") {
        self.forceFresh = forceFresh
        self.kind = kind
        // forceFresh skips the resume probe and always lands on the intro.
        self.phase = forceFresh ? .landing : .probing
    }

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    // MARK: - Derived

    var phaseIndex: Int {
        min(max(round?.phaseIndex ?? 0, 0), Self.phaseNames.count - 1)
    }

    var phaseName: String { Self.phaseNames[phaseIndex] }

    var showsStepper: Bool {
        phase == .answering || phase == .thinking
    }

    var canContinue: Bool {
        guard let round else { return false }
        return round.questions.allSatisfy { question in
            let draft = drafts[question.id] ?? AnswerDraft()
            if draft.skipped { return true }
            if !draft.selected.isEmpty { return true }
            return !draft.freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Probe / start

    /// On appear: resume an active round, jump to review if completed, or idle
    /// on the landing card when the server has nothing (404).
    func probe() async {
        guard !forceFresh, phase == .probing, let model else {
            if phase == .probing { phase = .landing }
            return
        }
        do {
            let active = try await model.api.interviewActive()
            sessionId = active.sessionId
            if let result = active.result ?? active.round?.result,
               active.status == "completed" || active.round?.done == true {
                self.round = active.round
                self.result = result
                phase = .reviewing
            } else if let round = active.round {
                enter(round)
            } else {
                phase = .landing
            }
        } catch {
            if Self.isNotFound(error) {
                phase = .landing
            } else {
                model.handle(error)
                phase = .probeFailed(TodayStore.message(for: error))
            }
        }
    }

    func retryProbe() async {
        phase = .probing
        await probe()
    }

    func begin() async {
        guard let model, !isStarting else { return }
        isStarting = true
        startError = nil
        defer { isStarting = false }
        do {
            // A forced restart abandons whatever draft still exists server-side.
            if forceFresh, let active = try? await model.api.interviewActive() {
                _ = try? await model.api.interviewAbandon(sessionId: active.sessionId)
            }
            let response = try await model.api.interviewStart(kind: kind)
            sessionId = response.sessionId
            transcript = []
            enter(response.round)
        } catch {
            model.handle(error)
            startError = TodayStore.message(for: error)
        }
    }

    // MARK: - Answering

    /// Builds the answer DTOs from the drafts, folds the round into the
    /// transcript, and sends. Retry re-sends the same payload.
    func submit() async {
        guard let round, phase == .answering, canContinue else { return }
        var answers: [InterviewAnswerDTO] = []
        for question in round.questions {
            let draft = drafts[question.id] ?? AnswerDraft()
            let text = draft.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
            if draft.skipped {
                answers.append(InterviewAnswerDTO(questionId: question.id, skipped: true))
            } else {
                // Preserve the option order the question presented.
                let options = question.options ?? []
                let ordered = options.filter { draft.selected.contains($0) }
                answers.append(InterviewAnswerDTO(
                    questionId: question.id,
                    selectedOptions: ordered,
                    freeText: text.isEmpty ? nil : text,
                ))
            }
            transcript.append(TranscriptEntry(kind: .qa(
                question: question.question,
                answer: Self.summary(for: draft),
                isFollowUp: question.isFollowUp,
            )))
        }
        pendingAnswers = answers
        phase = .thinking
        await send()
    }

    func retryAnswer() async {
        guard phase == .thinking else { return }
        await send()
    }

    private func send() async {
        guard let model, let sessionId else { return }
        answerError = nil
        do {
            let response = try await model.api.interviewAnswer(sessionId: sessionId, answers: pendingAnswers)
            if response.round.done {
                if let result = response.round.result {
                    self.round = response.round
                    self.result = result
                    phase = .reviewing
                } else {
                    answerError = "The interview finished without a plan draft. Try again."
                }
            } else {
                enter(response.round)
            }
        } catch {
            model.handle(error)
            answerError = TodayStore.message(for: error)
        }
    }

    private func enter(_ newRound: InterviewRoundDTO) {
        // Phase transitions render as divider rows in the transcript.
        if let previous = round, previous.phaseIndex != newRound.phaseIndex {
            let index = min(max(newRound.phaseIndex, 0), Self.phaseNames.count - 1)
            transcript.append(TranscriptEntry(kind: .phaseDivider(Self.phaseNames[index])))
        }
        round = newRound
        drafts = Dictionary(uniqueKeysWithValues: newRound.questions.map { ($0.id, AnswerDraft()) })
        answerError = nil
        phase = .answering
    }

    // MARK: - Exit / apply

    /// Best-effort server abandon; the caller dismisses regardless.
    func abandon() async {
        guard let model, let sessionId else { return }
        _ = try? await model.api.interviewAbandon(sessionId: sessionId)
    }

    func apply(startDate: DayKey) async {
        guard let model, let sessionId, let result, phase == .reviewing else { return }
        phase = .applying
        applyError = nil
        do {
            let request = ApplyPlanRequest(
                vision: result.visionDraft,
                profile: result.profile,
                areas: result.areas,
                block: ApplyBlockDTO(title: result.plan.blockTitle, startDate: startDate),
                goals: result.plan.goals,
            )
            _ = try await model.api.interviewApply(sessionId: sessionId, request)
            model.invalidateToday()
            phase = .done
        } catch {
            model.handle(error)
            applyError = TodayStore.message(for: error)
            phase = .reviewing
        }
    }

    // MARK: - Helpers

    private static func summary(for draft: AnswerDraft) -> String {
        if draft.skipped { return "Skipped" }
        var parts = draft.selected
        let text = draft.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { parts.append("“\(text)”") }
        return parts.joined(separator: " · ")
    }

    private static func isNotFound(_ error: Error) -> Bool {
        if case APIClientError.api(_, _, let status) = error { return status == 404 }
        return false
    }
}
