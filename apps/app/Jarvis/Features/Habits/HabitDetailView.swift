import DesignSystem
import JarvisAPI
import SwiftUI

/// Habit detail (§B3): this-week/today card, stats tiles, month calendar
/// with paging, and a reverse-chron history list with manual backfill.
struct HabitDetailView: View {
    let habitId: String
    var preloaded: HabitDTO?

    @Environment(AppModel.self) private var model

    @State private var habit: HabitDTO?
    @State private var stats: LoadState<HabitStatsResponse> = .idle
    @State private var calendar: LoadState<HabitCalendarResponse> = .idle
    /// Reps per dayKey for the current week (planned-days row + week card).
    @State private var weekReps: [String: Int] = [:]
    @State private var month: String = String(DayKeyMath.todayKey().prefix(7))
    @State private var showEditor = false
    @State private var errorMessage: String?

    private var todayKey: String { DayKeyMath.todayKey() }
    private var currentMonth: String { String(todayKey.prefix(7)) }

    /// The habit's own colour — its calendar, pace bar and stats all wear it,
    /// so arriving here from a blue row does not land you on a green screen.
    private var tintColor: Color {
        habit.map { HabitDisplay.color(for: $0).color } ?? .accentPrimary
    }

    var body: some View {
        Group {
            if let habit {
                content(habit)
            } else if let errorMessage {
                VStack(spacing: Space.lg) {
                    Text(errorMessage)
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
        .navigationTitle(habit?.name ?? "Habit")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditor = true }
                    .disabled(habit == nil)
            }
        }
        .sheet(isPresented: $showEditor) {
            if let habit {
                HabitEditorView(mode: .edit(habit)) {
                    Task { await load(forceHabitRefresh: true) }
                }
            }
        }
        .task { await load() }
        .onChange(of: model.dataRevision) {
            Task { await load(forceHabitRefresh: true) }
        }
        .onChange(of: month) {
            Task { await loadCalendar() }
        }
    }

    // MARK: - Loading

    private func load(forceHabitRefresh: Bool = false) async {
        if habit == nil, let preloaded {
            habit = preloaded
        }
        if habit == nil || forceHabitRefresh {
            do {
                let response = try await model.api.habits(includeArchived: true)
                if let found = response.habits.first(where: { $0.id == habitId }) {
                    habit = found
                }
            } catch {
                model.handle(error)
                if habit == nil {
                    errorMessage = TodayStore.message(for: error)
                    return
                }
            }
        }
        async let statsTask: Void = loadStats()
        async let calendarTask: Void = loadCalendar()
        _ = await (statsTask, calendarTask)
    }

    private func loadStats() async {
        do {
            stats = .loaded(try await model.api.habitStats(id: habitId))
        } catch {
            model.handle(error)
            if stats.value == nil { stats = .failed(TodayStore.message(for: error)) }
        }
    }

    private func loadCalendar() async {
        do {
            calendar = .loaded(try await model.api.habitCalendar(id: habitId, month: month))
            await loadWeekReps()
        } catch {
            model.handle(error)
            if calendar.value == nil { calendar = .failed(TodayStore.message(for: error)) }
        }
    }

    /// The current week can span a month boundary — fetch both months if so.
    private func loadWeekReps() async {
        let weekStart = HabitDisplay.weekStart(of: todayKey)
        let weekDays = (0..<7).map { DayKeyMath.addDays(weekStart, $0) }
        let months = Set(weekDays.map { String($0.prefix(7)) })

        var reps: [String: Int] = [:]
        for monthKey in months {
            let response: HabitCalendarResponse?
            if monthKey == month {
                response = calendar.value
            } else {
                response = try? await model.api.habitCalendar(id: habitId, month: monthKey)
            }
            for day in response?.days ?? [] where weekDays.contains(day.dayKey) {
                reps[day.dayKey] = day.reps
            }
        }
        weekReps = reps
    }

    // MARK: - Content

    private func content(_ habit: HabitDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if habit.type == .weeklyFrequency {
                    weekCard(habit)
                } else {
                    todayCard(habit)
                }
                statsRow(habit)
                calendarCard(habit)
                historySection(habit)
            }
            .padding(PageMargin.standard)
            #if os(macOS)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            #endif
        }
        .refreshable { await load(forceHabitRefresh: true) }
    }

    // MARK: - This-week card (weekly habits)

    private var weekTotal: Int { weekReps.values.reduce(0, +) }

    private func weekCard(_ habit: HabitDTO) -> some View {
        let target = habit.targetReps
        let total = weekTotal
        let status = HabitDisplay.weeklyStatus(total: total, target: target, dayKey: todayKey)

        return VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader("This week")

            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text("\(total) / \(target)")
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            PaceCapsule(
                target: target,
                done: total,
                expectedByTonight: HabitDisplay.expectedByTonight(target: target, dayKey: todayKey),
                status: status,
                tint: tintColor,
            )

            Text(weekLine(total: total, target: target, status: status))
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)

            plannedDaysRow(habit)

            Text("Planned days are suggestions. Only the weekly total counts.")
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func weekLine(total: Int, target: Int, status: PaceDisplayStatus) -> String {
        let remainingDays = 7 - HabitDisplay.weekdayIndex(of: todayKey) + 1
        switch status {
        case .weekDone:
            return "Week complete"
        case .onPace:
            return "On pace. \(target - total) more by Sunday"
        case .behind:
            return "Behind. Need \(target - total) in \(remainingDays) day\(remainingDays == 1 ? "" : "s")"
        case .outOfReach:
            return "Out of reach this week. Every rep still counts toward the total"
        }
    }

    private func plannedDaysRow(_ habit: HabitDTO) -> some View {
        let weekStart = HabitDisplay.weekStart(of: todayKey)
        let letters = ["M", "T", "W", "T", "F", "S", "S"]

        return HStack(spacing: Space.sm) {
            ForEach(0..<7, id: \.self) { offset in
                let dayKey = DayKeyMath.addDays(weekStart, offset)
                let planned = habit.plannedDays.contains(offset + 1)
                let reps = weekReps[dayKey] ?? 0
                plannedDayCell(letter: letters[offset], planned: planned, done: reps > 0)
            }
        }
    }

    @ViewBuilder
    private func plannedDayCell(letter: String, planned: Bool, done: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if done {
                    Circle().fill(Color.success)
                    Text(letter)
                        .font(.captionJ)
                        .foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(
                        planned ? Color.borderStrong : Color.borderHairline,
                        lineWidth: planned ? 1.5 : 1,
                    )
                    Text(letter)
                        .font(.captionJ)
                        .foregroundStyle(planned ? Color.textSecondary : Color.textTertiary)
                }
            }
            .frame(width: 28, height: 28)

            // Unplanned-but-done gets a tiny tick — the day-swap mechanic.
            if done, !planned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.success)
                    .background(Circle().fill(Color.bgSurface))
                    .offset(x: 3, y: -3)
            }
        }
    }

    // MARK: - Today card (daily / multi)

    private func todayCard(_ habit: HabitDTO) -> some View {
        let repsToday = weekReps[todayKey] ?? 0

        return VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader("Today")
            HStack(spacing: Space.lg) {
                RepPips(done: repsToday, target: habit.targetReps)
                Text("\(repsToday) of \(habit.targetReps) today")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button("Undo") {
                    Task { await unlog(dayKey: nil) }
                }
                .buttonStyle(.jarvisGhost)
                .disabled(repsToday == 0)
                Button(habit.type == .daily ? "Done" : "+1") {
                    Task { await log(dayKey: nil) }
                }
                .buttonStyle(.jarvisSecondary)
                .disabled(repsToday >= habit.targetReps)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Stats tiles

    private func statsRow(_ habit: HabitDTO) -> some View {
        let loaded = stats.value
        let rateKey = habit.type == .weeklyFrequency ? "last4Weeks" : "last30"
        let rateLabel = habit.type == .weeklyFrequency ? "4-week" : "30-day"
        let rate = loaded?.rates[rateKey] ?? nil

        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)],
            spacing: Space.md,
        ) {
            statTile(
                value: loaded.map { "\($0.streak.current) \($0.streak.unit)" } ?? Placeholder.noValue,
                label: "Current streak",
            )
            statTile(
                value: loaded.map { "\($0.streak.best) \($0.streak.unit)" } ?? Placeholder.noValue,
                label: "Best",
            )
            statTile(
                value: rate.map { "\(Int(($0 * 100).rounded()))%" } ?? Placeholder.noValue,
                label: rateLabel,
            )
            statTile(
                value: loaded.map { "\($0.totalReps)" } ?? Placeholder.noValue,
                label: "Total reps",
            )
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.captionJ)
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard(padding: Space.md)
    }

    // MARK: - Calendar

    private func calendarCard(_ habit: HabitDTO) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                SectionHeader(monthTitle)
                Spacer()
                Button {
                    month = addMonths(month, -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
                Button {
                    month = addMonths(month, 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(month >= currentMonth ? Color.textTertiary.opacity(0.4) : Color.textSecondary)
                .disabled(month >= currentMonth)
            }

            switch calendar {
            case .loaded(let response):
                CalendarDotGrid(
                    year: yearComponent,
                    month: monthComponent,
                    days: dotDays(response),
                    weekResults: habit.type == .weeklyFrequency ? weekResults(response) : nil,
                    tint: tintColor,
                )
            case .failed(let message):
                Text(message)
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            default:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private var yearComponent: Int { Int(month.prefix(4)) ?? 2000 }
    private var monthComponent: Int { Int(month.suffix(2)) ?? 1 }

    private var monthTitle: String {
        guard let date = DayKeyMath.date(from: "\(month)-01") else { return month }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private func addMonths(_ month: String, _ delta: Int) -> String {
        guard let date = DayKeyMath.date(from: "\(month)-01"),
              let shifted = Calendar.current.date(byAdding: .month, value: delta, to: date)
        else { return month }
        return String(DayKeyMath.dayFormatter.string(from: shifted).prefix(7))
    }

    private func dotDays(_ response: HabitCalendarResponse) -> [CalendarDay] {
        response.days.compactMap { day in
            guard let dayNumber = Int(day.dayKey.suffix(2)) else { return nil }
            let state: DotState = switch day.state {
            case "full":
                .full
            case "partial":
                .partial(day.credit ?? (day.target > 0 ? Double(day.reps) / Double(day.target) : 0))
            case "none":
                day.dayKey <= todayKey ? .missed : .notApplicable
            default:
                .notApplicable
            }
            return CalendarDay(day: dayNumber, state: state, isToday: day.dayKey == todayKey)
        }
    }

    private func weekResults(_ response: HabitCalendarResponse) -> [WeekResult]? {
        guard let weeks = response.weeks, !weeks.isEmpty else { return nil }
        return weeks.map { week in
            switch week.result {
            case "met": .met
            case "live": .live(done: week.total, target: week.target)
            default: .missed
            }
        }
    }

    // MARK: - History

    @ViewBuilder
    private func historySection(_ habit: HabitDTO) -> some View {
        let entries = (calendar.value?.days ?? [])
            .filter { $0.reps > 0 }
            .sorted { $0.dayKey > $1.dayKey }

        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("History")

            if entries.isEmpty {
                Text("Nothing logged this month")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { day in
                        historyRow(day, habit: habit)
                        if day.id != entries.last?.id {
                            Divider().overlay(Color.borderHairline)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func historyRow(_ day: CalendarDayDTO, habit: HabitDTO) -> some View {
        HStack(spacing: Space.md) {
            Text(HabitDisplay.shortLabel(for: day.dayKey))
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .frame(width: 60, alignment: .leading)

            Text(historyReps(day, habit: habit))
                .font(.monoJ)
                .foregroundStyle(Color.textSecondary)

            if day.state == "full" {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.success)
            }

            Spacer()

            // Manual backfill/correction: +1 / −1 on that specific day.
            Button {
                Task { await unlog(dayKey: day.dayKey) }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.bgSubtle, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textSecondary)

            Button {
                Task { await log(dayKey: day.dayKey) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.bgSubtle, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textSecondary)
        }
        .frame(minHeight: RowHeight.standard)
        .contextMenu {
            Button("Add one (\(HabitDisplay.shortLabel(for: day.dayKey)))") {
                Task { await log(dayKey: day.dayKey) }
            }
            Button("Remove one") {
                Task { await unlog(dayKey: day.dayKey) }
            }
        }
    }

    private func historyReps(_ day: CalendarDayDTO, habit: HabitDTO) -> String {
        switch habit.type {
        case .daily, .multiDaily:
            "\(day.reps)/\(habit.targetReps)"
        case .weeklyFrequency:
            "\(day.reps)×"
        }
    }

    // MARK: - Mutations

    private func log(dayKey: String?) async {
        do {
            _ = try await model.api.logHabit(id: habitId, dayKey: dayKey)
            model.invalidateToday() // triggers our own reload via onChange
        } catch {
            model.handle(error)
            errorMessage = nil // habit is loaded; surface via reload
        }
    }

    private func unlog(dayKey: String?) async {
        do {
            _ = try await model.api.unlogHabit(id: habitId, dayKey: dayKey)
            model.invalidateToday()
        } catch {
            model.handle(error)
        }
    }
}
