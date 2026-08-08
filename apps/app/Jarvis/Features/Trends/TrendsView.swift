import Charts
import DesignSystem
import JarvisAPI
import Observation
import SwiftUI

// MARK: - Store

enum TrendsRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var label: String { "\(rawValue)d" }
}

@Observable
@MainActor
final class TrendsStore {
    struct WeekColumn: Codable, Identifiable {
        let id: String // week-start dayKey
        let label: String
        let avg: Double?
    }

    struct WeeklyAverages: Codable {
        var currentAvg: Double?
        var previousAvg: Double?
        var columns: [WeekColumn]
    }

    struct HabitHeatRow: Codable, Identifiable {
        var id: String { habit.id }
        let habit: HabitDTO
        let days: [CalendarDayDTO]
    }

    private(set) var scores: LoadState<[ScorePointDTO]> = .idle
    private(set) var weekly: LoadState<WeeklyAverages> = .idle
    private(set) var heatmap: LoadState<[HabitHeatRow]> = .idle

    private var model: AppModel?

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    func load(range: TrendsRange, force: Bool = false) async {
        if force, let model {
            model.invalidate([.score, .habit, .mood, .task])
            weekly = .idle
            heatmap = .idle
        }
        async let scoresLoad: Void = loadScores(range: range)
        async let weeklyLoad: Void = loadWeekly()
        async let heatmapLoad: Void = loadHeatmap()
        _ = await (scoresLoad, weeklyLoad, heatmapLoad)
    }

    func loadScores(range: TrendsRange) async {
        guard let model else { return }
        let cacheKey = CacheKey.trendScores(range: String(range.rawValue))
        if let cached = model.store.read([ScorePointDTO].self, cacheKey) {
            scores = .loaded(cached.value)
            if cached.isFresh { return }
        }
        if scores.value == nil { scores = .loading }
        do {
            let today = DayKeyMath.todayKey()
            let response = try await model.api.scores(
                from: DayKeyMath.addDays(today, -(range.rawValue - 1)),
                to: today,
            )
            let sorted = response.scores.sorted { $0.dayKey < $1.dayKey }
            scores = .loaded(sorted)
            model.store.write(sorted, cacheKey)
        } catch {
            model.handle(error)
            scores = .failed(TodayStore.message(for: error))
        }
    }

    /// Current vs previous week + 8-week mini columns. Uses the server's
    /// weekly aggregates when a block exists; otherwise groups raw scores
    /// by ISO week client-side.
    private func loadWeekly() async {
        guard let model, weekly.value == nil else { return }
        if let cached = model.store.read(WeeklyAverages.self, .trendWeekly) {
            weekly = .loaded(cached.value)
            if cached.isFresh { return }
        }
        if weekly.value == nil { weekly = .loading }
        let today = DayKeyMath.todayKey()
        do {
            weekly = .loaded(try await computedWeekly(model.api, today: today))
        } catch {
            model.handle(error)
            if weekly.value == nil { weekly = .failed(TodayStore.message(for: error)) }
        }
        if let loaded = weekly.value { model.store.write(loaded, .trendWeekly) }
    }

    private func computedWeekly(_ api: APIClient, today: DayKey) async throws -> WeeklyAverages {
        let currentWeekStart = HabitDisplay.weekStart(of: today)
        let from = DayKeyMath.addDays(currentWeekStart, -49) // 8 weeks total
        let points = try await api.scores(from: from, to: today).scores

        var byWeek: [DayKey: [Double?]] = [:]
        for point in points {
            byWeek[HabitDisplay.weekStart(of: point.dayKey), default: []].append(point.total)
        }
        let columns = (0..<8).map { offset -> WeekColumn in
            let start = DayKeyMath.addDays(currentWeekStart, -7 * (7 - offset))
            return WeekColumn(
                id: start,
                label: HabitDisplay.shortLabel(for: start),
                avg: ScoreBands.average(byWeek[start] ?? []),
            )
        }
        return WeeklyAverages(
            currentAvg: ScoreBands.average(byWeek[currentWeekStart] ?? []),
            previousAvg: ScoreBands.average(byWeek[DayKeyMath.addDays(currentWeekStart, -7)] ?? []),
            columns: columns,
        )
    }

    /// One current-month calendar row per active habit.
    private func loadHeatmap() async {
        guard let model, heatmap.value == nil else { return }
        if let cached = model.store.read([HabitHeatRow].self, .trendHeatmap) {
            heatmap = .loaded(cached.value)
            if cached.isFresh { return }
        }
        heatmap = .loading
        do {
            let month = String(DayKeyMath.todayKey().prefix(7))
            let habits = try await model.api.habits().habits
                .filter { $0.archivedAt == nil && $0.pausedAt == nil }
            var rows: [HabitHeatRow] = []
            for habit in habits {
                let days = (try? await model.api.habitCalendar(id: habit.id, month: month))?.days ?? []
                rows.append(HabitHeatRow(habit: habit, days: days.sorted { $0.dayKey < $1.dayKey }))
            }
            heatmap = .loaded(rows)
            model.store.write(rows, .trendHeatmap)
        } catch {
            model.handle(error)
            heatmap = .failed(TodayStore.message(for: error))
        }
    }
}

// MARK: - View

/// Trends (§B3): range picker → daily score chart → weekly averages →
/// component small multiples → habit consistency heatmap. Every point
/// taps through to that day's breakdown.
struct TrendsView: View {
    @Environment(AppModel.self) private var model

    @State private var store = TrendsStore()
    @State private var range: TrendsRange = .week
    @State private var breakdownRoute: BreakdownRoute?
    /// Content width of the heatmap card, used to size a month of dots to fit.
    @State private var heatWidth: CGFloat = 0

    private struct BreakdownRoute: Identifiable {
        let dayKey: DayKey
        var id: String { dayKey }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                ChipPicker(TrendsRange.allCases, selection: $range) { $0.label }

                dailyScoreCard
                weeklyAveragesCard
                componentSplitCard
                habitHeatmapCard
            }
            .padding(PageMargin.standard)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color.bgCanvas)
        .navigationTitle("Trends")
        .sheet(item: $breakdownRoute) { route in
            ScoreBreakdownSheet(dayKey: route.dayKey)
        }
        .task {
            store.configure(model)
            await store.load(range: range)
        }
        .onChange(of: range) {
            Task { await store.loadScores(range: range) }
        }
        .refreshable {
            await store.load(range: range, force: true)
        }
    }

    // MARK: - Daily score chart

    @ViewBuilder
    private var dailyScoreCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Daily score")

            switch store.scores {
            case .loaded(let points):
                if points.allSatisfy({ $0.total == nil }) {
                    emptyLine("No scored days in this range yet")
                } else if range == .week {
                    weekBars(points)
                } else {
                    trendLine(points)
                }
            case .failed(let message):
                emptyLine(message)
            default:
                loadingBlock(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func weekBars(_ points: [ScorePointDTO]) -> some View {
        let today = DayKeyMath.todayKey()
        return Chart {
            bandZones
            ForEach(points) { point in
                if let date = DayKeyMath.date(from: point.dayKey) {
                    if point.dayKey == today {
                        // Today: accent outline behind the band-tinted bar.
                        BarMark(
                            x: .value("Day", date, unit: .day),
                            y: .value("Score", point.total ?? 0),
                            width: .fixed(26),
                        )
                        .foregroundStyle(Color.accentPrimary)
                        BarMark(
                            x: .value("Day", date, unit: .day),
                            yStart: .value("Base", 0),
                            yEnd: .value("Score", max((point.total ?? 0) - 2, 0)),
                            width: .fixed(20),
                        )
                        .foregroundStyle(ScoreBands.color(point.total))
                    } else {
                        BarMark(
                            x: .value("Day", date, unit: .day),
                            y: .value("Score", point.total ?? 0),
                            width: .fixed(22),
                        )
                        .foregroundStyle(ScoreBands.color(point.total))
                        .cornerRadius(3)
                    }
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis { scoreYAxis }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) {
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(height: 180)
        .chartOverlay { proxy in
            tapCatcher(proxy: proxy, points: points)
        }
    }

    private func trendLine(_ points: [ScorePointDTO]) -> some View {
        let smoothed = movingAverage(points)
        return Chart {
            bandZones
            ForEach(points) { point in
                if let date = DayKeyMath.date(from: point.dayKey), let total = point.total {
                    LineMark(
                        x: .value("Day", date, unit: .day),
                        y: .value("Score", total),
                        series: .value("Series", "raw"),
                    )
                    .foregroundStyle(Color.accentPrimary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            ForEach(smoothed, id: \.0) { dayKey, value in
                if let date = DayKeyMath.date(from: dayKey) {
                    LineMark(
                        x: .value("Day", date, unit: .day),
                        y: .value("7-day avg", value),
                        series: .value("Series", "avg"),
                    )
                    .foregroundStyle(Color.accentPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis { scoreYAxis }
        .chartXAxis {
            AxisMarks {
                AxisValueLabel()
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(height: 180)
        .chartOverlay { proxy in
            tapCatcher(proxy: proxy, points: points)
        }
    }

    /// Faint horizontal band zones behind the marks (gray / amber / green).
    private var bandZones: some ChartContent {
        ForEach([(0.0, 50.0, Color.textTertiary), (50, 70, .warning), (70, 100, .success)], id: \.0) { zone in
            RectangleMark(
                yStart: .value("From", zone.0),
                yEnd: .value("To", zone.1),
            )
            .foregroundStyle(zone.2.opacity(0.05))
        }
    }

    private var scoreYAxis: some AxisContent {
        AxisMarks(values: [0, 50, 70, 100]) {
            AxisGridLine().foregroundStyle(Color.borderHairline)
            AxisValueLabel().font(.captionJ).foregroundStyle(Color.textTertiary)
        }
    }

    /// Trailing 7-day moving average over the non-nil totals.
    private func movingAverage(_ points: [ScorePointDTO]) -> [(DayKey, Double)] {
        points.indices.compactMap { index in
            let window = points[max(index - 6, 0)...index].compactMap(\.total)
            guard !window.isEmpty else { return nil }
            return (points[index].dayKey, window.reduce(0, +) / Double(window.count))
        }
    }

    /// Transparent overlay translating taps into the nearest day's breakdown.
    private func tapCatcher(proxy: ChartProxy, points: [ScorePointDTO]) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard let plotFrame = proxy.plotFrame else { return }
                    let x = location.x - geo[plotFrame].origin.x
                    guard let tapped: Date = proxy.value(atX: x) else { return }
                    let nearest = points.min { lhs, rhs in
                        distance(lhs.dayKey, to: tapped) < distance(rhs.dayKey, to: tapped)
                    }
                    if let nearest {
                        breakdownRoute = BreakdownRoute(dayKey: nearest.dayKey)
                    }
                }
        }
    }

    private func distance(_ dayKey: DayKey, to date: Date) -> TimeInterval {
        guard let day = DayKeyMath.date(from: dayKey) else { return .infinity }
        return abs(day.timeIntervalSince(date))
    }

    // MARK: - Weekly averages

    @ViewBuilder
    private var weeklyAveragesCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Weekly average")

            switch store.weekly {
            case .loaded(let data):
                weeklyContent(data)
            case .failed(let message):
                emptyLine(message)
            default:
                loadingBlock(height: 90)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    @ViewBuilder
    private func weeklyContent(_ data: TrendsStore.WeeklyAverages) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Text(data.currentAvg.map { "\(Int($0.rounded()))" } ?? "—")
                .font(.title1J)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            if let current = data.currentAvg, let previous = data.previousAvg {
                let diff = Int((current - previous).rounded())
                Text("\(diff >= 0 ? "▲" : "▼")\(abs(diff))")
                    .font(.monoJ)
                    .foregroundStyle(diff >= 0 ? Color.success : Color.warning)
                Text("vs last week")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("this week")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            }
        }

        // Weeks before the account had any data are dead space that also
        // crowds the axis labels — start the chart at the first scored week.
        let columns = Array(data.columns.drop { $0.avg == nil })
        if !columns.isEmpty {
            Chart(columns) { column in
                BarMark(
                    x: .value("Week", column.label),
                    y: .value("Avg", column.avg ?? 0),
                    width: .fixed(columns.count > 5 ? 16 : 28),
                )
                .foregroundStyle(ScoreBands.color(column.avg))
                .cornerRadius(3)
                .annotation(position: .top, spacing: 2) {
                    Text(column.avg.map { "\(Int($0.rounded()))" } ?? "")
                        .font(.captionJ)
                        .monospacedDigit()
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .chartYScale(domain: 0...110) // headroom for the value labels
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks {
                    AxisValueLabel().font(.captionJ).foregroundStyle(Color.textTertiary)
                }
            }
            .frame(height: 76)
        }
    }

    // MARK: - Component split

    /// Answers "which part of my score is holding it back". Three unlabelled
    /// sparklines could not: with hidden axes and no numbers there was no way
    /// to tell what any line was worth. Each row now states the average points
    /// earned per scored day against that component's weight, so the weakest
    /// component is obvious at a glance.
    @ViewBuilder
    private var componentSplitCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("What's driving your score")

            switch store.scores {
            case .loaded(let points):
                if points.allSatisfy({ $0.taskPoints == nil && $0.habitPoints == nil && $0.feelPoints == nil }) {
                    emptyLine("Nothing scored in this range yet")
                } else {
                    Text("Average points per scored day, out of each part's weight.")
                        .font(.captionJ)
                        .foregroundStyle(Color.textTertiary)

                    let w = weights
                    componentRow("Tasks", points: points, value: \.taskPoints, weight: w.tasks, color: .accentPrimary)
                    componentRow("Habits", points: points, value: \.habitPoints, weight: w.habits, color: .success)
                    componentRow("Feel", points: points, value: \.feelPoints, weight: w.feel, color: .warning)
                }
            case .failed(let message):
                emptyLine(message)
            default:
                loadingBlock(height: 150)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private var weights: (tasks: Double, habits: Double, feel: Double) {
        guard let w = model.settings?.scoreWeights else { return (40, 40, 20) }
        return (w.tasks, w.habits, w.feel)
    }

    private func componentRow(
        _ label: String,
        points: [ScorePointDTO],
        value: KeyPath<ScorePointDTO, Double?>,
        weight: Double,
        color: Color,
    ) -> some View {
        // Only days that actually scored this component count — averaging in
        // days it did not apply to would understate it.
        let scored = points.compactMap { $0[keyPath: value] }
        let average = scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)
        let fraction = average.map { min(max($0 / max(weight, 1), 0), 1) }

        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(label)
                    .font(.subheadJ)
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: Space.sm)
                Text(average.map { "\(TodayView.formatPoints($0)) / \(TodayView.formatPoints(weight))" } ?? "—")
                    .font(.monoJ)
                    .monospacedDigit()
                    .foregroundStyle(average == nil ? Color.textTertiary : Color.textPrimary)
                Text(fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(.captionJ)
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 38, alignment: .trailing)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bgSubtle)
                    if let fraction {
                        Capsule()
                            .fill(color)
                            .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 3 : 0))
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(label): \(average.map { "\(TodayView.formatPoints($0)) of \(TodayView.formatPoints(weight))" } ?? "no data")",
        )
    }

    // MARK: - Habit heatmap

    @ViewBuilder
    private var habitHeatmapCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Habit consistency") {
                Text(monthLabel)
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }

            switch store.heatmap {
            case .loaded(let rows):
                if rows.isEmpty {
                    emptyLine("No active habits")
                } else {
                    ForEach(rows) { row in
                        heatRow(row, dotSize: HeatDotMetrics.size(width: heatWidth, dayCount: row.days.count))
                    }
                    heatLegend
                }
            case .failed(let message):
                emptyLine(message)
            default:
                loadingBlock(height: 80)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Measured on the card's content, so the dots can be sized to fill the
        // row exactly instead of being a fixed 8pt that left a dead gap at the
        // trailing edge — most visible on Mac, where the card is twice as wide.
        .background {
            GeometryReader { proxy in
                Color.clear.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { heatWidth = $0 }
            }
        }
        .jarvisCard()
    }

    private var monthLabel: String {
        DayKeyMath.date(from: DayKeyMath.todayKey())?
            .formatted(.dateTime.month(.wide)) ?? ""
    }

    private func heatRow(_ row: TrendsStore.HabitHeatRow, dotSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(row.habit.name)
                .font(.subheadJ)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            HStack(spacing: dotSize * HeatDotMetrics.spacingRatio) {
                ForEach(row.days) { day in
                    heatDot(day, size: dotSize)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            breakdownRoute = BreakdownRoute(dayKey: day.dayKey)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Space.xs)
    }

    /// Simplified calendar-dot language: solid = full, half-opacity = partial,
    /// outline = applicable-but-missed, faint dot = N/A. Never red.
    @ViewBuilder
    private func heatDot(_ day: CalendarDayDTO, size: CGFloat) -> some View {
        switch day.state {
        case "full":
            Circle().fill(Color.success).frame(width: size, height: size)
        case "partial":
            Circle().fill(Color.success.opacity(0.45)).frame(width: size, height: size)
        case "none":
            Circle()
                .strokeBorder(Color.borderStrong, lineWidth: max(1, size * 0.1))
                .frame(width: size, height: size)
        default:
            Circle().fill(Color.bgSubtle).frame(width: size, height: size)
        }
    }

    /// The dots carry four distinct meanings; without this they are just dots.
    private var heatLegend: some View {
        HStack(spacing: Space.md) {
            legendItem(Circle().fill(Color.success), "done")
            legendItem(Circle().fill(Color.success.opacity(0.45)), "partial")
            legendItem(Circle().strokeBorder(Color.borderStrong, lineWidth: 1), "missed")
            legendItem(Circle().fill(Color.bgSubtle), "not due")
            Spacer(minLength: 0)
        }
        .padding(.top, Space.xs)
    }

    private func legendItem(_ shape: some View, _ label: String) -> some View {
        HStack(spacing: Space.xs) {
            shape.frame(width: 8, height: 8)
            Text(label)
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Shared bits

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.subheadJ)
            .foregroundStyle(Color.textTertiary)
    }

    private func loadingBlock(height: CGFloat) -> some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}
