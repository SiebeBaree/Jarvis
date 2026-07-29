import Charts
import DesignSystem
import JarvisAPI
import SwiftUI

/// Score Breakdown (§B3): today's payload passed in directly, or a dayKey
/// for a read-only historical day (fetched on open). Ring + per-component
/// cards + 7-day bar chart.
struct ScoreBreakdownSheet: View {
    private enum Source {
        case today(DayPayload)
        case historical(DayKey)
    }

    private let source: Source

    init(payload: DayPayload) {
        source = .today(payload)
    }

    init(dayKey: DayKey) {
        source = .historical(dayKey)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var day: LoadState<DayPayload> = .idle
    @State private var chart: LoadState<[ScorePointDTO]> = .idle

    private var dayKey: DayKey {
        switch source {
        case .today(let payload): payload.dayKey
        case .historical(let key): key
        }
    }

    private var title: String {
        switch source {
        case .today: "Score Breakdown"
        case .historical(let key): HabitDisplay.shortLabel(for: key)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let payload = day.value {
                    content(payload)
                } else if case .failed(let message) = day {
                    VStack(spacing: Space.lg) {
                        Text(message)
                            .font(.bodyJ)
                            .foregroundStyle(Color.textSecondary)
                        Button("Retry") {
                            Task { await load() }
                        }
                        .buttonStyle(.jarvisSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.bgCanvas)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 620)
        #endif
        .task { await load() }
    }

    private func load() async {
        switch source {
        case .today(let payload):
            day = .loaded(payload)
        case .historical(let key):
            if day.value == nil {
                day = .loading
                do {
                    day = .loaded(try await model.api.day(key))
                } catch {
                    model.handle(error)
                    day = .failed(TodayStore.message(for: error))
                    return
                }
            }
        }
        if chart.value == nil {
            chart = .loading
            do {
                let response = try await model.api.scores(from: DayKeyMath.addDays(dayKey, -6), to: dayKey)
                chart = .loaded(response.scores.sorted { $0.dayKey < $1.dayKey })
            } catch {
                model.handle(error)
                chart = .failed(TodayStore.message(for: error))
            }
        }
    }

    // MARK: - Content

    private var weights: (tasks: Double, habits: Double, feel: Double) {
        guard let w = model.settings?.scoreWeights else { return (40, 40, 20) }
        return (w.tasks, w.habits, w.feel)
    }

    private func content(_ payload: DayPayload) -> some View {
        ScrollView {
            VStack(spacing: Space.lg) {
                ring(payload)
                    .padding(.vertical, Space.sm)
                tasksCard(payload)
                habitsCard(payload)
                feelCard(payload)
                sevenDayCard
                Text("Weights: \(Int(weights.tasks))/\(Int(weights.habits))/\(Int(weights.feel))")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(PageMargin.standard)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private func ring(_ payload: DayPayload) -> some View {
        ScoreRing(size: 160, total: payload.score.total, caption: isToday ? "today" : "score")
    }

    private var isToday: Bool {
        if case .today = source { return true }
        return false
    }

    // MARK: - Tasks card

    private func tasksCard(_ payload: DayPayload) -> some View {
        let entries = payload.score.breakdown.tasks
        let completed = entries.filter { $0.credit >= 1 }.count

        return VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Tasks")
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(summaryLine(
                    count: entries.isEmpty ? nil : "\(completed) of \(entries.count) completed",
                    points: payload.score.taskPoints,
                    weight: weights.tasks,
                ))
                .font(.monoJ)
                .foregroundStyle(Color.textSecondary)
            }

            if entries.isEmpty {
                Text("No tasks due — component skipped")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            } else {
                VStack(spacing: Space.sm) {
                    ForEach(entries, id: \.taskId) { entry in
                        taskRow(entry, payload: payload)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func taskRow(_ entry: BreakdownTaskDTO, payload: DayPayload) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: entry.credit >= 1 ? "checkmark" : "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(entry.credit >= 1 ? Color.success : Color.textTertiary)
                .frame(width: 16)
            Text(taskTitle(for: entry.taskId, payload: payload))
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            if entry.late {
                TagChip("late")
            }
            Spacer(minLength: Space.sm)
            if entry.credit > 0, entry.credit < 1 {
                Text("\(Int((entry.credit * 100).rounded()))%")
                    .font(.monoJ)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func taskTitle(for taskId: String, payload: DayPayload) -> String {
        let all = payload.tasksDue + payload.overdueTasks
        if let task = all.first(where: { $0.id == taskId }) { return task.title }
        if let subtask = all.lazy.flatMap(\.subtasks).first(where: { $0.id == taskId }) { return subtask.title }
        return "Task"
    }

    // MARK: - Habits card

    private func habitsCard(_ payload: DayPayload) -> some View {
        let entries = payload.score.breakdown.habits

        return VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Habits")
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(summaryLine(count: nil, points: payload.score.habitPoints, weight: weights.habits))
                    .font(.monoJ)
                    .foregroundStyle(Color.textSecondary)
            }

            if entries.isEmpty {
                Text("No active habits — component skipped")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            } else {
                VStack(spacing: Space.sm) {
                    ForEach(entries, id: \.habitId) { entry in
                        habitRow(entry, payload: payload)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func habitRow(_ entry: BreakdownHabitDTO, payload: DayPayload) -> some View {
        let today = payload.habits.first { $0.habit.id == entry.habitId }

        return HStack(spacing: Space.sm) {
            Text(today?.habit.name ?? "Habit")
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Space.sm)
            if let today {
                Text(repsText(for: today))
                    .font(.monoJ)
                    .foregroundStyle(Color.textSecondary)
            }
            Text("→ \(Int((entry.credit * 100).rounded()))%")
                .font(.monoJ)
                .foregroundStyle(entry.credit >= 1 ? Color.success : Color.textSecondary)
        }
    }

    private func repsText(for entry: HabitTodayEntryDTO) -> String {
        switch entry.habit.type {
        case .daily, .multiDaily:
            "\(entry.repsToday)/\(entry.habit.targetReps)"
        case .weeklyFrequency:
            "\(entry.weekTotal)/\(entry.habit.targetReps) this week"
        }
    }

    // MARK: - Feel card

    private func feelCard(_ payload: DayPayload) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Feel")
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let feelPoints = payload.score.feelPoints {
                    Text("\(TodayView.formatPoints(feelPoints))/\(TodayView.formatPoints(weights.feel))")
                        .font(.monoJ)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            if let mood = payload.mood, let feelPoints = payload.score.feelPoints {
                Text("\(mood.value) → \(TodayView.formatPoints(feelPoints))/\(TodayView.formatPoints(weights.feel)) pts")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("Not set — score renormalized over \(Int(payload.score.applicableWeight)) pts")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - 7-day chart

    @ViewBuilder
    private var sevenDayCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("7-Day")

            switch chart {
            case .loaded(let points):
                sevenDayChart(points)
            case .failed:
                Text("Could not load the score trend")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            default:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func sevenDayChart(_ points: [ScorePointDTO]) -> some View {
        Chart {
            ForEach(points) { point in
                if point.dayKey == dayKey {
                    // Selected day: accent outline behind the band-tinted bar.
                    BarMark(
                        x: .value("Day", axisLabel(point.dayKey)),
                        y: .value("Score", point.total ?? 0),
                        width: .fixed(24),
                    )
                    .foregroundStyle(Color.accentPrimary)
                    BarMark(
                        x: .value("Day", axisLabel(point.dayKey)),
                        yStart: .value("Base", 0),
                        yEnd: .value("Score", max((point.total ?? 0) - 2, 0)),
                        width: .fixed(18),
                    )
                    .foregroundStyle(bandColor(point.total))
                } else {
                    BarMark(
                        x: .value("Day", axisLabel(point.dayKey)),
                        y: .value("Score", point.total ?? 0),
                        width: .fixed(20),
                    )
                    .foregroundStyle(bandColor(point.total))
                    .cornerRadius(3)
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) {
                AxisGridLine().foregroundStyle(Color.borderHairline)
                AxisValueLabel().font(.captionJ).foregroundStyle(Color.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks {
                AxisValueLabel().font(.captionJ).foregroundStyle(Color.textTertiary)
            }
        }
        .frame(height: 140)
    }

    /// Universal score bands: gray <50, amber 50–69, green ≥70.
    private func bandColor(_ total: Double?) -> Color {
        guard let total else { return .bgSubtle }
        if total < 50 { return .textTertiary }
        if total < 70 { return .warning }
        return .success
    }

    private func axisLabel(_ key: DayKey) -> String {
        guard let date = DayKeyMath.date(from: key) else { return key }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func summaryLine(count: String?, points: Double?, weight: Double) -> String {
        let pointsText = points.map { "\(TodayView.formatPoints($0))/\(TodayView.formatPoints(weight))" } ?? "—"
        if let count { return "\(count) · \(pointsText)" }
        return pointsText
    }
}
