import DesignSystem
import JarvisAPI
import SwiftUI

/// Week Detail (§B3): "Week 7 · Jul 7–13" — seven day-score dots
/// (tap → historical Score Breakdown) → tactics checklist for that week →
/// completed tasks that week (collapsed disclosure).
struct WeekDetailView: View {
    let store: PlanStore
    let weekNumber: Int

    @Environment(AppModel.self) private var model

    @State private var scores: LoadState<[ScorePointDTO]> = .idle
    @State private var completedTasks: LoadState<[TaskDTO]> = .idle
    @State private var breakdownDay: DayRoute?
    @State private var showCompletedTasks = false

    private struct DayRoute: Identifiable {
        let dayKey: DayKey
        var id: String { dayKey }
    }

    private var block: BlockDTO? { store.content.value?.block }
    private var weekStart: DayKey? { block.map { PlanDisplay.weekStart(block: $0, weekNumber: weekNumber) } }
    private var weekEnd: DayKey? { block.map { PlanDisplay.weekEnd(block: $0, weekNumber: weekNumber) } }
    /// Tactic toggles are only editable for the current week — past weeks
    /// are a read-only record.
    private var isEditable: Bool {
        store.currentWeekNumber.map { weekNumber == $0 } ?? false
    }

    var body: some View {
        Group {
            if let block {
                content(block)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle(block.map { PlanDisplay.weekLabel(block: $0, weekNumber: weekNumber) } ?? "Week \(weekNumber)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $breakdownDay) { route in
            ScoreBreakdownSheet(dayKey: route.dayKey)
        }
        .task { await load() }
        .onChange(of: model.dataRevision) {
            Task { await load() }
        }
    }

    private func load() async {
        guard let weekStart, let weekEnd else { return }
        do {
            async let scoresResponse = model.api.scores(from: weekStart, to: weekEnd)
            async let tasksResponse = model.api.tasks(view: "done")
            let (scoresList, tasksList) = try await (scoresResponse, tasksResponse)
            scores = .loaded(scoresList.scores.sorted { $0.dayKey < $1.dayKey })
            completedTasks = .loaded(
                tasksList.tasks.filter { task in
                    guard let day = task.completedAt.map({ String($0.prefix(10)) }) else { return false }
                    return day >= weekStart && day <= weekEnd
                },
            )
        } catch {
            model.handle(error)
            if scores.value == nil { scores = .failed(TodayStore.message(for: error)) }
            if completedTasks.value == nil { completedTasks = .failed(TodayStore.message(for: error)) }
        }
    }

    // MARK: - Content

    private func content(_ block: BlockDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if let error = store.mutationError {
                    Text(error)
                        .font(.subheadJ)
                        .foregroundStyle(Color.textSecondary)
                        .padding(Space.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
                dayDotsCard
                tacticsSection
                completedTasksSection
            }
            .padding(PageMargin.standard)
            #if os(macOS)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            #endif
        }
        .refreshable { await load() }
    }

    // MARK: - Day dots

    private var dayDotsCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Day Scores")
            switch scores {
            case .loaded(let points):
                dayDots(points)
            case .failed:
                Text("Could not load this week's scores")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            default:
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func dayDots(_ points: [ScorePointDTO]) -> some View {
        let today = DayKeyMath.todayKey()
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                if let weekStart {
                    let dayKey = DayKeyMath.addDays(weekStart, offset)
                    let point = points.first { $0.dayKey == dayKey }
                    dayDot(dayKey: dayKey, total: point?.total, tappable: dayKey <= today)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dayDot(dayKey: DayKey, total: Double?, tappable: Bool) -> some View {
        Button {
            breakdownDay = DayRoute(dayKey: dayKey)
        } label: {
            VStack(spacing: Space.xs) {
                Text(weekdayInitial(dayKey))
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
                Circle()
                    .fill(total != nil ? PlanDisplay.bandColor(total) : Color.clear)
                    .overlay(Circle().strokeBorder(total == nil ? Color.borderStrong : Color.clear, lineWidth: 1))
                    .frame(width: 22, height: 22)
                Text(total.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(total == nil ? Color.textTertiary : Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
        .accessibilityLabel("\(HabitDisplay.shortLabel(for: dayKey)) score \(total.map { "\(Int($0.rounded()))" } ?? "not set")")
    }

    private func weekdayInitial(_ dayKey: DayKey) -> String {
        guard let date = DayKeyMath.date(from: dayKey) else { return "" }
        return String(date.formatted(.dateTime.weekday(.abbreviated)).prefix(2))
    }

    // MARK: - Tactics

    @ViewBuilder
    private var tacticsSection: some View {
        SectionHeader("Tactics")
            .padding(.top, Space.xs)

        let entries = store.tactics(forWeek: weekNumber)
        if entries.isEmpty {
            Text(weekNumber == 13 ? "Review week — no tactics scheduled" : "No tactics scheduled this week")
                .font(.subheadJ)
                .foregroundStyle(Color.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(entries, id: \.tactic.id) { entry in
                    tacticRow(entry.tactic, goal: entry.goal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisCard()
        }
    }

    private func tacticRow(_ tactic: TacticDTO, goal: GoalWithProgressDTO) -> some View {
        let done = store.completedWeeks(for: tactic).contains(weekNumber)
        return HStack(spacing: Space.md) {
            Button {
                Task { await store.setTacticWeek(tactic, weekNumber: weekNumber, done: !done) }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(done ? Color.success : Color.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!isEditable)

            VStack(alignment: .leading, spacing: 1) {
                Text(tactic.title)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(goal.title)
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Completed tasks

    @ViewBuilder
    private var completedTasksSection: some View {
        if let tasks = completedTasks.value, !tasks.isEmpty {
            Button {
                withAnimation(.easeOut(duration: 0.25)) { showCompletedTasks.toggle() }
            } label: {
                HStack(spacing: Space.xs) {
                    Text("Completed tasks (\(tasks.count))")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: showCompletedTasks ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, Space.sm)

            if showCompletedTasks {
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(tasks) { task in
                        HStack(spacing: Space.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .light))
                                .foregroundStyle(Color.success)
                            Text(task.title)
                                .font(.subheadJ)
                                .foregroundStyle(Color.textSecondary)
                                .strikethrough(true, color: .textTertiary)
                                .lineLimit(1)
                            Spacer(minLength: Space.sm)
                            if let day = task.completedAt.map({ String($0.prefix(10)) }) {
                                Text(HabitDisplay.shortLabel(for: day))
                                    .font(.captionJ)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .jarvisCard(padding: Space.md)
            }
        }
    }
}
