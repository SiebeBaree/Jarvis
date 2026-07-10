import Charts
import DesignSystem
import JarvisAPI
import Observation
import SwiftUI

// MARK: - Recap data

/// Everything the weekly recap cards need, fetched up front.
struct WeeklyRecapData {
    var weekNumber: Int?
    var scores: [ScorePointDTO]
    var habits: [HabitTodayEntryDTO]
    var goals: [GoalWithProgressDTO]
}

/// Everything the block (week-13) recap cards need.
struct BlockRecapData {
    struct HabitTotal: Identifiable {
        var id: String { habit.id }
        let habit: HabitDTO
        let totalReps: Int
        let bestStreak: StreakDTO?
    }

    struct MetricDelta: Identifiable {
        var id: String { type.id }
        let type: MetricTypeDTO
        let first: MetricEntryDTO
        let last: MetricEntryDTO
    }

    var block: BlockDTO
    var weeks: [WeeklyScoreDTO]
    var goals: [GoalWithProgressDTO]
    var habitTotals: [HabitTotal]
    var metricDeltas: [MetricDelta]
    var daysScored: Int
    var avgScore: Double?
    var bestWeek: WeeklyScoreDTO?
}

enum RecapData {
    case weekly(WeeklyRecapData)
    case block(BlockRecapData)
}

// MARK: - Store

@Observable
@MainActor
final class ReviewRecapStore {
    private(set) var state: LoadState<RecapData> = .idle
    private var model: AppModel?

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    func load(kind: ReviewKind) async {
        guard let model, state.value == nil else { return }
        state = .loading
        do {
            switch kind {
            case .weekly:
                state = .loaded(.weekly(try await loadWeekly(model.api)))
            case .block:
                state = .loaded(.block(try await loadBlock(model.api)))
            }
        } catch {
            model.handle(error)
            state = .failed(TodayStore.message(for: error))
        }
    }

    func retry(kind: ReviewKind) async {
        state = .idle
        await load(kind: kind)
    }

    private func loadWeekly(_ api: APIClient) async throws -> WeeklyRecapData {
        let payload = try await api.today()

        // The week under review: this week on Sunday, last week on Monday.
        var reviewWeek = payload.weekNumber ?? 1
        if HabitDisplay.weekdayIndex(of: payload.dayKey) == 1 {
            reviewWeek = max(reviewWeek - 1, 1)
        }
        let weekStart: DayKey
        if let block = payload.block {
            weekStart = DayKeyMath.addDays(block.startDate, (reviewWeek - 1) * 7)
        } else {
            weekStart = HabitDisplay.weekStart(of: payload.dayKey)
        }

        // Habit weekTotals must come from the reviewed week's Sunday — on
        // Monday `today()` already carries the NEW week's totals. Clamp to
        // today so a mid-week launch still resolves to a real day.
        let reviewSunday = min(DayKeyMath.addDays(weekStart, 6), payload.dayKey)

        async let scoresResponse = api.scores(from: weekStart, to: DayKeyMath.addDays(weekStart, 6))
        async let blockResponse = api.currentBlock()
        async let reviewedDayResponse = api.day(reviewSunday)
        let (scores, current, reviewedDay) = try await (scoresResponse, blockResponse, reviewedDayResponse)

        return WeeklyRecapData(
            weekNumber: payload.block == nil ? nil : reviewWeek,
            scores: scores.scores.sorted { $0.dayKey < $1.dayKey },
            habits: reviewedDay.habits,
            goals: current.goals,
        )
    }

    private func loadBlock(_ api: APIClient) async throws -> BlockRecapData {
        let current = try await api.currentBlock()
        guard let block = current.block else {
            throw APIClientError.api(code: "no_block", message: "No active block to review.", status: 404)
        }

        let today = DayKeyMath.todayKey()
        let scoresTo = min(today, block.endDate)

        async let weeksResponse = api.weeklyScores(blockId: block.id)
        async let habitsResponse = api.habits()
        async let scoresResponse = api.scores(from: block.startDate, to: scoresTo)
        async let metricTypesResponse = api.metricTypes()
        let (weeks, habits, scores, metricTypes) = try await (
            weeksResponse, habitsResponse, scoresResponse, metricTypesResponse,
        )

        // Per-habit block totals via stats (best-effort — a miss shows 0).
        var habitTotals: [BlockRecapData.HabitTotal] = []
        for habit in habits.habits.filter({ $0.archivedAt == nil }) {
            let stats = try? await api.habitStats(id: habit.id)
            habitTotals.append(BlockRecapData.HabitTotal(
                habit: habit,
                totalReps: stats?.totalReps ?? 0,
                bestStreak: stats?.streak,
            ))
        }

        // Body deltas: first vs last entry per metric type inside the block.
        var metricDeltas: [BlockRecapData.MetricDelta] = []
        for type in metricTypes.metricTypes.filter({ $0.archivedAt == nil }).prefix(3) {
            let entries = (try? await api.metricEntries(typeId: type.id, from: block.startDate, to: scoresTo))?
                .entries.sorted { $0.dayKey < $1.dayKey } ?? []
            if let first = entries.first, let last = entries.last, first.id != last.id {
                metricDeltas.append(BlockRecapData.MetricDelta(type: type, first: first, last: last))
            }
        }

        let totals = scores.scores.map(\.total)
        let realWeeks = weeks.weeks.filter { $0.weekNumber <= 12 }
        return BlockRecapData(
            block: block,
            weeks: weeks.weeks,
            goals: current.goals,
            habitTotals: habitTotals,
            metricDeltas: metricDeltas,
            daysScored: totals.compactMap { $0 }.count,
            avgScore: ScoreBands.average(totals),
            bestWeek: realWeeks.filter { $0.avg != nil }.max { ($0.avg ?? 0) < ($1.avg ?? 0) },
        )
    }
}

// MARK: - Deck view

/// Phase 1 of the review flow: swipeable stat cards (3 weekly / 5 block)
/// with a pinned Continue button (§B3).
struct ReviewRecapDeck: View {
    let kind: ReviewKind
    let onContinue: () -> Void

    @Environment(AppModel.self) private var model
    @State private var store = ReviewRecapStore()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch store.state {
                case .loaded(let data):
                    deck(data)
                case .failed(let message):
                    VStack(spacing: Space.lg) {
                        Text(message)
                            .font(.bodyJ)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await store.retry(kind: kind) }
                        }
                        .buttonStyle(.jarvisSecondary)
                    }
                    .padding(PageMargin.standard)
                default:
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            continueBar
        }
        .task {
            store.configure(model)
            await store.load(kind: kind)
        }
    }

    private var continueBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderHairline)
                .frame(height: 0.5)
            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.jarvisPrimary)
            .disabled(store.state.value == nil)
            .opacity(store.state.value == nil ? 0.5 : 1)
            .frame(maxWidth: 560)
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.md)
        }
        .background(Color.bgCanvas)
    }

    @ViewBuilder
    private func deck(_ data: RecapData) -> some View {
        let cards = recapCards(data)
        #if os(iOS)
        TabView {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                ScrollView {
                    card
                        .padding(.horizontal, PageMargin.standard)
                        .padding(.top, Space.lg)
                        .padding(.bottom, Space.xxxl)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        #else
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Space.lg) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    card
                        .frame(width: 320)
                }
            }
            .padding(PageMargin.standard)
        }
        #endif
    }

    private func recapCards(_ data: RecapData) -> [AnyView] {
        switch data {
        case .weekly(let weekly):
            [
                AnyView(WeeklyScoresCard(data: weekly)),
                AnyView(WeeklyHabitsCard(habits: weekly.habits)),
                AnyView(RecapGoalsCard(goals: weekly.goals, showProgress: false)),
            ]
        case .block(let block):
            [
                AnyView(BlockScoreLineCard(weeks: block.weeks)),
                AnyView(RecapGoalsCard(goals: block.goals, showProgress: true)),
                AnyView(BlockHabitTotalsCard(totals: block.habitTotals)),
                AnyView(BlockBodyCard(deltas: block.metricDeltas)),
                AnyView(BlockStatGridCard(data: block)),
            ]
        }
    }
}

// MARK: - Weekly cards

/// Card 1: avg/best/worst + 7-day band-tinted mini bars.
private struct WeeklyScoresCard: View {
    let data: WeeklyRecapData

    private var totals: [Double?] { data.scores.map(\.total) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader(data.weekNumber.map { "Week \($0) scores" } ?? "Week scores")

            HStack(spacing: Space.xxl) {
                stat("Avg", ScoreBands.average(totals))
                stat("Best", totals.compactMap { $0 }.max())
                stat("Worst", totals.compactMap { $0 }.min())
            }

            if data.scores.isEmpty {
                Text("No scored days this week")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            } else {
                Chart(data.scores) { point in
                    BarMark(
                        x: .value("Day", dayLabel(point.dayKey)),
                        y: .value("Score", point.total ?? 0),
                        width: .fixed(18),
                    )
                    .foregroundStyle(ScoreBands.color(point.total))
                    .cornerRadius(3)
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
                .frame(height: 120)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func stat(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map { "\(Int($0.rounded()))" } ?? "—")
                .font(.title2J)
                .monospacedDigit()
                .foregroundStyle(ScoreBands.color(value))
            Text(label)
                .font(.captionJ)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func dayLabel(_ key: DayKey) -> String {
        guard let date = DayKeyMath.date(from: key) else { return key }
        return date.formatted(.dateTime.weekday(.narrow))
    }
}

/// Card 2: per-habit met/missed rows against the weekly target.
private struct WeeklyHabitsCard: View {
    let habits: [HabitTodayEntryDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Habits")

            if habits.isEmpty {
                Text("No active habits this week")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            } else {
                ForEach(habits) { entry in
                    let target = weekTarget(entry.habit)
                    let met = entry.weekTotal >= target
                    HStack(spacing: Space.sm) {
                        Image(systemName: met ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(met ? Color.success : Color.textTertiary)
                        Text(entry.habit.name)
                            .font(.bodyJ)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: Space.sm)
                        Text("\(entry.weekTotal)/\(target)")
                            .font(.monoJ)
                            .foregroundStyle(met ? Color.success : Color.textSecondary)
                    }
                    .frame(minHeight: 28)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    /// Reps expected for a full week per habit type.
    private func weekTarget(_ habit: HabitDTO) -> Int {
        switch habit.type {
        case .daily: 7
        case .multiDaily: habit.targetReps * 7
        case .weeklyFrequency: habit.targetReps
        }
    }
}

/// Weekly card 3 / block card 2: goal rows with status pills (+ progress).
private struct RecapGoalsCard: View {
    let goals: [GoalWithProgressDTO]
    let showProgress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Goals")

            if goals.isEmpty {
                Text("No goals in this block")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            } else {
                ForEach(goals) { goal in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.sm) {
                            Text(goal.title)
                                .font(.bodyJ)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(2)
                            Spacer(minLength: Space.sm)
                            ReviewStatusPill(status: goal.trackStatus ?? "")
                        }
                        if showProgress {
                            let fraction = goal.manualProgress.map { Double($0) / 100 } ?? goal.progress ?? 0
                            HStack(spacing: Space.sm) {
                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.bgSubtle)
                                        Capsule()
                                            .fill(Color.accentPrimary)
                                            .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                                    }
                                }
                                .frame(height: 4)
                                Text("\(Int((fraction * 100).rounded()))%")
                                    .font(.monoJ)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }
}

// MARK: - Block cards

/// Block card 1: 12-week score line.
private struct BlockScoreLineCard: View {
    let weeks: [WeeklyScoreDTO]

    private var scored: [WeeklyScoreDTO] {
        weeks.filter { $0.avg != nil }.sorted { $0.weekNumber < $1.weekNumber }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader("12 weeks")

            if scored.isEmpty {
                Text("No scored weeks yet")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            } else {
                Chart(scored) { week in
                    LineMark(
                        x: .value("Week", week.weekNumber),
                        y: .value("Avg", week.avg ?? 0),
                    )
                    .foregroundStyle(Color.accentPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(
                        x: .value("Week", week.weekNumber),
                        y: .value("Avg", week.avg ?? 0),
                    )
                    .foregroundStyle(ScoreBands.color(week.avg))
                    .symbolSize(30)
                }
                .chartYScale(domain: 0...100)
                .chartXScale(domain: 1...13)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) {
                        AxisGridLine().foregroundStyle(Color.borderHairline)
                        AxisValueLabel().font(.captionJ).foregroundStyle(Color.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: [1, 4, 7, 10, 13]) {
                        AxisValueLabel().font(.captionJ).foregroundStyle(Color.textTertiary)
                    }
                }
                .frame(height: 140)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }
}

/// Block card 3: per-habit block totals + best streak.
private struct BlockHabitTotalsCard: View {
    let totals: [BlockRecapData.HabitTotal]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Habits · 12 weeks")

            if totals.isEmpty {
                Text("No habits in this block")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            } else {
                ForEach(totals) { row in
                    HStack(spacing: Space.sm) {
                        Image(systemName: HabitDisplay.icon(for: row.habit))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 20)
                        Text(row.habit.name)
                            .font(.bodyJ)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: Space.sm)
                        if let streak = row.bestStreak, streak.best >= 2 {
                            Text("best \(streak.best) \(streak.unit)")
                                .font(.captionJ)
                                .foregroundStyle(Color.textTertiary)
                        }
                        Text("\(row.totalReps) reps")
                            .font(.monoJ)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(minHeight: 28)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }
}

/// Block card 4: first vs last metric values across the block.
private struct BlockBodyCard: View {
    let deltas: [BlockRecapData.MetricDelta]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Body")

            if deltas.isEmpty {
                Text("No body metrics logged this block")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            } else {
                ForEach(deltas) { delta in
                    HStack(spacing: Space.sm) {
                        Text(delta.type.name)
                            .font(.bodyJ)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: Space.sm)
                        Text("\(format(delta.first.value, delta.type)) → \(format(delta.last.value, delta.type)) \(delta.type.unit)")
                            .font(.monoJ)
                            .foregroundStyle(deltaColor(delta))
                    }
                    .frame(minHeight: 28)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func format(_ value: Double, _ type: MetricTypeDTO) -> String {
        String(format: "%.\(max(type.decimals, 0))f", value)
    }

    private func deltaColor(_ delta: BlockRecapData.MetricDelta) -> Color {
        let change = delta.last.value - delta.first.value
        switch delta.type.goalDirection {
        case "down": return change < 0 ? .success : (change > 0 ? .warning : .textSecondary)
        case "up": return change > 0 ? .success : (change < 0 ? .warning : .textSecondary)
        default: return .textSecondary
        }
    }
}

/// Block card 5: stat grid (days scored / avg / best week / weeks elapsed).
private struct BlockStatGridCard: View {
    let data: BlockRecapData

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader("Block stats")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.lg) {
                tile("Days scored", "\(data.daysScored)")
                tile("Avg score", data.avgScore.map { "\(Int($0.rounded()))" } ?? "—")
                tile("Best week", data.bestWeek.map { "W\($0.weekNumber) · \(Int(($0.avg ?? 0).rounded()))" } ?? "—")
                tile("Weeks scored", "\(data.weeks.filter { $0.avg != nil }.count)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2J)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.captionJ)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}
