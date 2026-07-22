import DesignSystem
import JarvisAPI
import SwiftUI

/// The Today screen (§B3, Stage 1): score header, mood card, overdue,
/// tasks, and habits. Briefing card, week chip, and evening wrap-up are
/// later stages and slot in above/below these sections.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = TodayStore()
    @State private var showSettings = false
    @State private var showBreakdown = false
    @State private var showCompleted = false
    @State private var isAddingTask = false
    @State private var newTaskTitle = ""
    @State private var quickDueChoice: QuickDueChoice = .today
    @State private var quickPriority: TaskPriority = .medium
    @State private var quickCategories: [TaskCategoryDTO] = []
    @State private var quickCategoryId: String?
    @State private var showQuickEditor = false
    @State private var quickEditorGoals: [GoalDTO] = []
    @State private var detailRoute: HabitDetailRoute?
    @State private var showPlanOnboarding = false
    @FocusState private var addTaskFocused: Bool

    /// Due-date choice for the quick-add composer chips.
    private enum QuickDueChoice {
        case today, tomorrow, none

        var label: String {
            switch self {
            case .today: "Today"
            case .tomorrow: "Tomorrow"
            case .none: "No date"
            }
        }
    }

    var body: some View {
        Group {
            if let payload = store.payload {
                content(payload)
            } else if case .failed(let message) = store.day {
                errorState(message)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle("Today")
        .toolbar {
            // Settings lives in the sidebar on macOS; only iPhone needs the gear.
            #if os(iOS)
            ToolbarItem(placement: .navigation) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            // Trends (and Body inside it) + Improve live behind these on
            // iPhone; macOS reaches them via the sidebar.
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    ImproveView()
                } label: {
                    Image(systemName: "sparkles")
                }
                .accessibilityLabel("Improve")
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    TrendsView()
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                .accessibilityLabel("Trends")
            }
            #endif
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 520)
                #endif
        }
        .sheet(isPresented: $showBreakdown) {
            if let payload = store.payload {
                ScoreBreakdownSheet(payload: payload)
            }
        }
        .sheet(isPresented: $showQuickEditor) {
            TaskEditorView(
                goals: quickEditorGoals,
                defaultDueDate: store.payload?.dayKey ?? DayKeyMath.todayKey(),
                initialTitle: newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            ) {
                newTaskTitle = ""
                isAddingTask = false
            }
        }
        .navigationDestination(item: $detailRoute) { route in
            HabitDetailView(
                habitId: route.habitId,
                preloaded: store.payload?.habits.first(where: { $0.habit.id == route.habitId })?.habit,
            )
        }
        .setupWizardCover(isPresented: $showPlanOnboarding)
        .task {
            store.configure(model)
            await store.load()
        }
        .onChange(of: model.todayRevision) {
            Task { await store.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.load() }
            }
        }
    }

    // MARK: - Content

    private func content(_ payload: DayPayload) -> some View {
        List {
            Group {
                dateHeader(payload)
                if let error = store.mutationError {
                    errorBanner(error)
                }
                if payload.block == nil {
                    if let upcoming = payload.upcomingBlock {
                        upcomingBlockBanner(upcoming)
                    } else {
                        planSetupBanner
                    }
                }
                BriefingSlot(payload: payload) // Stage 3: morning briefing card
                scoreHeader(payload)
                moodSection(payload)
                CheckinPromptCard() // weekly improvement-area photo prompt
                WeeklyReviewSlot(payload: payload) // Stage 4: weekly review banner
                WrapupSlot(payload: payload) // Stage 3: evening wrap-up banner
                if !payload.overdueTasks.isEmpty {
                    overdueSection(payload)
                }
                if payload.isReviewWeek {
                    reviewWeekTasksNote(payload)
                    if !payload.tasksDue.isEmpty {
                        tasksSection(payload)
                    }
                } else {
                    tasksSection(payload)
                }
                habitsSection(payload)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: Space.xs, leading: PageMargin.standard,
                bottom: Space.xs, trailing: PageMargin.standard,
            ))
            #if os(macOS)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            #endif
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.load(force: true) }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Space.lg) {
            Text(message)
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await store.load() }
            }
            .buttonStyle(.jarvisSecondary)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Space.sm) {
            Text(message)
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
            Spacer(minLength: Space.sm)
            Button("Retry") {
                store.mutationError = nil
                Task { await store.load() }
            }
            .buttonStyle(.plain)
            .font(.subheadJ)
            .foregroundStyle(Color.accentPrimary)
        }
        .padding(Space.md)
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: - Date header

    private func dateHeader(_ payload: DayPayload) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DayKeyMath.longLabel(for: payload.dayKey))
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
            if DayKeyMath.isLateNight() {
                Text("Late night — still counts for \(weekdayName(payload.dayKey))")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }
            if let block = payload.block, let weekNumber = payload.weekNumber {
                Button {
                    model.requestedSection = .plan
                } label: {
                    Text(payload.isReviewWeek
                        ? "Review Week · \(block.title)"
                        : "Week \(weekNumber) · \(block.title)")
                        .font(.captionJ)
                        .foregroundStyle(payload.isReviewWeek ? Color.accentPrimary : Color.textSecondary)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 3)
                        .background(payload.isReviewWeek ? Color.accentSubtle : Color.bgSubtle, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, Space.xs)
                .accessibilityHint(Text("Opens the Plan tab"))
            }
        }
    }

    private func weekdayName(_ dayKey: String) -> String {
        guard let date = DayKeyMath.date(from: dayKey) else { return "today" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    // MARK: - Plan setup banner

    /// Shown while no 12-week block exists — routes into the setup wizard.
    private var planSetupBanner: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Set up your 12-week plan")
                .font(.headlineJ)
                .foregroundStyle(Color.textPrimary)
            Text("You write the goals and habits — Jarvis tracks the execution.")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
            Button("Set up your plan") {
                showPlanOnboarding = true
            }
            .buttonStyle(.jarvisPrimary)
            .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    /// A block exists but hasn't started yet — no setup nagging.
    private func upcomingBlockBanner(_ block: BlockSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("\"\(block.title)\" starts \(HabitDisplay.shortLabel(for: block.startDate))")
                .font(.headlineJ)
                .foregroundStyle(Color.textPrimary)
            Text("Your plan is ready. Habits and mood score every day; block tasks and tactics begin with week 1.")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Review week (tasks paused)

    private func reviewWeekTasksNote(_ payload: DayPayload) -> some View {
        let hidden = payload.pausedTaskCount ?? 0
        return VStack(alignment: .leading, spacing: Space.xs) {
            Text("Review week — tasks are paused")
                .font(.headlineJ)
                .foregroundStyle(Color.textPrimary)
            Text(
                hidden > 0
                    ? "\(hidden) scheduled task\(hidden == 1 ? "" : "s") hidden until the next block. Habits and mood keep scoring."
                    : "Habits and mood keep scoring. Use this week to close out the block.",
            )
            .font(.subheadJ)
            .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Score header

    private var weights: (tasks: Double, habits: Double, feel: Double) {
        guard let w = model.settings?.scoreWeights else { return (40, 40, 20) }
        return (w.tasks, w.habits, w.feel)
    }

    private func scoreHeader(_ payload: DayPayload) -> some View {
        let score = payload.score
        let w = weights
        let feelFill = score.feelPoints.map { $0 / max(w.feel, 1) }

        return HStack(spacing: Space.xl) {
            ScoreRing(size: 120, total: score.total)
            VStack(alignment: .leading, spacing: Space.md) {
                componentRow(label: "Tasks", points: score.taskPoints, weight: w.tasks, color: .accentPrimary)
                componentRow(label: "Habits", points: score.habitPoints, weight: w.habits, color: .success)
                componentRow(
                    label: "Feel",
                    points: score.feelPoints,
                    weight: w.feel,
                    color: .warning.mix(with: .success, by: feelFill ?? 0),
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
        .contentShape(Rectangle())
        .onTapGesture { showBreakdown = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Shows the score breakdown"))
    }

    private func componentRow(label: String, points: Double?, weight: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                Spacer(minLength: Space.sm)
                Text(points.map { "\(Self.formatPoints($0))/\(Self.formatPoints(weight))" } ?? "—")
                    .font(.monoJ)
                    .foregroundStyle(Color.textPrimary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bgSubtle)
                    if let points, weight > 0 {
                        Capsule()
                            .fill(color)
                            .frame(width: proxy.size.width * min(max(points / weight, 0), 1))
                    }
                }
            }
            .frame(height: 4)
        }
    }

    static func formatPoints(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }

    // MARK: - Mood

    @ViewBuilder
    private func moodSection(_ payload: DayPayload) -> some View {
        MoodCard(mood: payload.mood) { value in
            Task { await store.setMood(value) }
        }
        if payload.yesterdayMoodMissing,
           !store.backfillSkipped,
           Calendar.current.component(.hour, from: .now) < 12 {
            MoodBackfillRow(
                onCommit: { value in Task { await store.setYesterdayMood(value) } },
                onSkip: { store.backfillSkipped = true },
            )
        }
    }

    // MARK: - Overdue

    @ViewBuilder
    private func overdueSection(_ payload: DayPayload) -> some View {
        Text("OVERDUE")
            .font(.captionJ)
            .tracking(0.6)
            .foregroundStyle(Color.warning)
            .padding(.top, Space.sm)

        ForEach(payload.overdueTasks) { task in
            TaskRow(
                task: task,
                overdueLabel: task.dueDate.map { "was due \(HabitDisplay.shortLabel(for: $0))" },
                onToggle: { Task { await store.completeTask(task) } },
                onTap: {},
            )
            .swipeActions(edge: .trailing) {
                Button("Complete") { Task { await store.completeTask(task) } }
                    .tint(.success)
            }
            .swipeActions(edge: .leading) {
                Button("Today") { Task { await store.rescheduleTask(task, to: payload.dayKey) } }
                    .tint(.accentPrimary)
                Button("Tomorrow") {
                    Task { await store.rescheduleTask(task, to: DayKeyMath.addDays(payload.dayKey, 1)) }
                }
                .tint(.textTertiary)
            }
        }
    }

    // MARK: - Tasks

    private func sortedOpenTasks(_ payload: DayPayload) -> [TaskDTO] {
        payload.tasksDue
            .filter { $0.status == .open }
            .sorted { lhs, rhs in
                let lp = priorityRank(lhs.priority)
                let rp = priorityRank(rhs.priority)
                if lp != rp { return lp < rp }
                switch (lhs.dueTime, rhs.dueTime) {
                case (let l?, let r?) where l != r: return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                default: return lhs.sortOrder < rhs.sortOrder
                }
            }
    }

    private func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }

    @ViewBuilder
    private func tasksSection(_ payload: DayPayload) -> some View {
        let open = sortedOpenTasks(payload)
        let completed = payload.tasksDue.filter { $0.status == .done }

        SectionHeader(payload.isReviewWeek ? "Scheduled anyway" : "Tasks")
            .padding(.top, Space.sm)

        if payload.tasksDue.isEmpty, payload.overdueTasks.isEmpty {
            if payload.habits.isEmpty {
                heroEmptyState
            } else {
                Text("Nothing scheduled today")
                    .font(.bodyJ)
                    .foregroundStyle(Color.textTertiary)
            }
        }

        ForEach(open) { task in
            TaskRow(
                task: task,
                onToggle: { Task { await store.completeTask(task) } },
                onTap: {},
            )
            .swipeActions(edge: .trailing) {
                Button("Complete") { Task { await store.completeTask(task) } }
                    .tint(.success)
            }
        }

        // Quick-add is hidden during review week — the server filters new
        // tasks out of the paused list, so they would vanish on refresh.
        if !payload.isReviewWeek {
            addTaskRow
        }

        if !completed.isEmpty {
            Button {
                withAnimation(.easeOut(duration: 0.25)) { showCompleted.toggle() }
            } label: {
                HStack(spacing: Space.xs) {
                    Text("Completed (\(completed.count))")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if showCompleted {
                ForEach(completed) { task in
                    TaskRow(
                        task: task,
                        onToggle: { Task { await store.uncompleteTask(task) } },
                        onTap: {},
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var addTaskRow: some View {
        if isAddingTask {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.md) {
                    Image(systemName: "circle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Color.textTertiary)
                    TextField("Task title", text: $newTaskTitle)
                        .font(.headlineJ)
                        .textFieldStyle(.plain)
                        .focused($addTaskFocused)
                        .onSubmit { submitQuickTask() }
                    Button("Cancel") {
                        isAddingTask = false
                        newTaskTitle = ""
                    }
                    .buttonStyle(.plain)
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
                }
                HStack(spacing: Space.sm) {
                    quickDueChip
                    quickPriorityChip
                    quickCategoryChip
                    Spacer(minLength: Space.sm)
                    Button("More…") { openFullEditor() }
                        .buttonStyle(.jarvisGhost)
                }
                .padding(.leading, 22 + Space.md)
            }
            .frame(minHeight: RowHeight.standard)
        } else {
            Button {
                isAddingTask = true
                quickDueChoice = .today
                quickPriority = .medium
                quickCategoryId = nil
                addTaskFocused = true
                Task {
                    if let response = try? await model.api.taskCategories() {
                        quickCategories = response.categories
                    }
                }
            } label: {
                Text("+ Add task")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.jarvisGhost)
        }
    }

    private var quickDueChip: some View {
        Menu {
            Button("Today") { quickDueChoice = .today }
            Button("Tomorrow") { quickDueChoice = .tomorrow }
            Button("None") { quickDueChoice = .none }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                Text(quickDueChoice.label)
                    .font(.captionJ)
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 3)
            .background(Color.bgSubtle, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Due date: \(quickDueChoice.label)")
    }

    private var quickPriorityChip: some View {
        Menu {
            Button("P1 High") { quickPriority = .high }
            Button("P2 Medium") { quickPriority = .medium }
            Button("P3 Low") { quickPriority = .low }
        } label: {
            PriorityFlag(quickPriority.flagLevel)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, 3)
                .background(Color.bgSubtle, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Priority: \(quickPriority.flagLevel.label)")
    }

    @ViewBuilder
    private var quickCategoryChip: some View {
        if !quickCategories.isEmpty {
            Menu {
                Button("None") { quickCategoryId = nil }
                ForEach(quickCategories) { category in
                    Button(category.name) { quickCategoryId = category.id }
                }
            } label: {
                HStack(spacing: Space.xs) {
                    Image(systemName: "tag")
                        .font(.system(size: 10))
                    Text(quickCategories.first(where: { $0.id == quickCategoryId })?.name ?? "Category")
                        .font(.captionJ)
                }
                .foregroundStyle(quickCategoryId == nil ? Color.textSecondary : Color.accentPrimary)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, 3)
                .background(quickCategoryId == nil ? Color.bgSubtle : Color.accentSubtle, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(
                "Category: \(quickCategories.first(where: { $0.id == quickCategoryId })?.name ?? "none")",
            )
        }
    }

    /// "More…" hands the typed title to the full editor (goals fetched lazily).
    private func openFullEditor() {
        Task {
            if let response = try? await model.api.goals() {
                quickEditorGoals = response.goals
            }
            showQuickEditor = true
        }
    }

    private func submitQuickTask() {
        let title = newTaskTitle
        let dueDate: String? = {
            guard let dayKey = store.payload?.dayKey else { return nil }
            switch quickDueChoice {
            case .today: return dayKey
            case .tomorrow: return DayKeyMath.addDays(dayKey, 1)
            case .none: return nil
            }
        }()
        let priority = quickPriority
        let categoryId = quickCategoryId
        newTaskTitle = ""
        isAddingTask = false
        Task {
            await store.createQuickTask(title: title, dueDate: dueDate, priority: priority, categoryId: categoryId)
        }
    }

    private var heroEmptyState: some View {
        VStack(spacing: Space.sm) {
            Text("Start by adding your first task or habit")
                .font(.headlineJ)
                .foregroundStyle(Color.textPrimary)
            Text("Today fills in as you plan your day.")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
    }

    // MARK: - Habits

    @ViewBuilder
    private func habitsSection(_ payload: DayPayload) -> some View {
        SectionHeader("Habits")
            .padding(.top, Space.sm)

        if payload.habits.isEmpty {
            if !payload.tasksDue.isEmpty || !payload.overdueTasks.isEmpty {
                HStack(spacing: Space.sm) {
                    Text("No habits yet — create them in the Habits tab")
                        .font(.bodyJ)
                        .foregroundStyle(Color.textTertiary)
                    Button("Open Habits") {
                        model.requestedSection = .habits
                    }
                    .buttonStyle(.jarvisGhost)
                }
            }
        } else {
            let alsoAvailable = payload.habits.filter { isAlsoAvailable($0) }
            let active = payload.habits.filter { !isAlsoAvailable($0) }

            ForEach(active) { entry in
                habitRow(entry, payload: payload, subdued: false)
            }

            if !alsoAvailable.isEmpty {
                Text("ALSO AVAILABLE")
                    .font(.captionJ)
                    .tracking(0.6)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, Space.xs)

                ForEach(alsoAvailable) { entry in
                    habitRow(entry, payload: payload, subdued: true)
                }
            }
        }
    }

    private func isAlsoAvailable(_ entry: HabitTodayEntryDTO) -> Bool {
        entry.habit.type == .weeklyFrequency && !entry.plannedToday && entry.repsToday == 0
    }

    private func habitRow(_ entry: HabitTodayEntryDTO, payload: DayPayload, subdued: Bool) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: HabitDisplay.icon(for: entry.habit))
                .font(.system(size: 15))
                .foregroundStyle(subdued ? Color.textTertiary : Color.textSecondary)
                .frame(width: 24)

            Text(entry.habit.name)
                .font(.headlineJ)
                .foregroundStyle(subdued ? Color.textTertiary : Color.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Space.sm)

            habitControl(entry, payload: payload)
        }
        .frame(minHeight: RowHeight.standard)
        .contentShape(Rectangle())
        .onTapGesture { detailRoute = HabitDetailRoute(habitId: entry.habit.id) }
        .contextMenu {
            Button("Undo last") {
                Task { await store.unlogHabit(entry.habit.id) }
            }
            .disabled(entry.repsToday == 0)
            Button("View details") {
                detailRoute = HabitDetailRoute(habitId: entry.habit.id)
            }
        }
    }

    @ViewBuilder
    private func habitControl(_ entry: HabitTodayEntryDTO, payload: DayPayload) -> some View {
        switch entry.habit.type {
        case .daily:
            Button {
                Task {
                    if entry.repsToday > 0 {
                        await store.unlogHabit(entry.habit.id)
                    } else {
                        await store.logHabit(entry.habit.id)
                    }
                }
            } label: {
                Image(systemName: entry.repsToday > 0 ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(entry.repsToday > 0 ? Color.success : Color.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

        case .multiDaily:
            HStack(spacing: Space.md) {
                RepPips(done: entry.repsToday, target: entry.habit.targetReps)
                logCapsuleButton(
                    disabled: entry.repsToday >= entry.habit.targetReps,
                    action: { Task { await store.logHabit(entry.habit.id) } },
                )
                .contextMenu {
                    Button("Undo last") {
                        Task { await store.unlogHabit(entry.habit.id) }
                    }
                    .disabled(entry.repsToday == 0)
                }
            }

        case .weeklyFrequency:
            HStack(spacing: Space.md) {
                PaceCapsule(
                    target: entry.habit.targetReps,
                    done: entry.weekTotal,
                    expectedByTonight: HabitDisplay.expectedByTonight(
                        target: entry.habit.targetReps,
                        dayKey: payload.dayKey,
                    ),
                    status: HabitDisplay.paceStatus(entry.pace),
                )
                .frame(maxWidth: 190)
                logCapsuleButton(
                    disabled: false,
                    action: { Task { await store.logHabit(entry.habit.id) } },
                )
            }
        }
    }

    private func logCapsuleButton(disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("+1")
                .font(.monoJ)
                .foregroundStyle(disabled ? Color.textTertiary : Color.accentPrimary)
                .padding(.horizontal, Space.md)
                .padding(.vertical, 5)
                .background(Color.bgSubtle, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel("Log one")
    }
}

// MARK: - Mood card

/// "How do you feel today?" gradient slider (0–100). Unset = hollow knob,
/// "—" value chip, faint accent card tint. Commits on drag end.
private struct MoodCard: View {
    let mood: MoodDTO?
    let onCommit: (Int) -> Void

    @State private var value: Double = 50
    @State private var isDragging = false

    private var isSet: Bool { mood != nil || isDragging }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("How do you feel today?")
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(isSet ? "\(Int(value.rounded()))" : "—")
                    .font(.monoJ)
                    .foregroundStyle(isSet ? Color.textPrimary : Color.textTertiary)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, 3)
                    .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            }
            MoodSlider(value: $value, isSet: isSet, isDragging: $isDragging, onCommit: onCommit)
        }
        .padding(Space.lg)
        .background(
            mood == nil ? Color.accentSubtle.opacity(0.45) : Color.bgSurface,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous),
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.borderHairline, lineWidth: 0.5),
        )
        .onAppear {
            if let mood { value = Double(mood.value) }
        }
        .onChange(of: mood?.value) { _, newValue in
            if let newValue, !isDragging { value = Double(newValue) }
        }
    }
}

/// Backfill row: "Yesterday's feel?" mini slider + Skip.
private struct MoodBackfillRow: View {
    let onCommit: (Int) -> Void
    let onSkip: () -> Void

    @State private var value: Double = 50
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: Space.md) {
            Text("Yesterday's feel?")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
                .layoutPriority(1)
            MoodSlider(value: $value, isSet: isDragging, isDragging: $isDragging, onCommit: onCommit)
            Button("Skip", action: onSkip)
                .buttonStyle(.jarvisGhost)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .background(Color.bgSubtle.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// Custom 0–100 slider over the mood gradient. `Slider` can't tint its track
/// with a gradient cross-platform, so this draws its own track + knob.
struct MoodSlider: View {
    @Binding var value: Double
    var isSet: Bool
    @Binding var isDragging: Bool
    let onCommit: (Int) -> Void

    private let knobSize: CGFloat = 22
    private let trackHeight: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let usable = max(proxy.size.width - knobSize, 1)
            let knobX = CGFloat(value / 100) * usable

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient.moodGradient)
                    .frame(height: trackHeight)
                    .opacity(isSet ? 1 : 0.35)
                    .padding(.horizontal, knobSize / 2)

                knob
                    .offset(x: knobX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let fraction = (gesture.location.x - knobSize / 2) / usable
                        value = min(max(Double(fraction) * 100, 0), 100)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onCommit(Int(value.rounded()))
                    },
            )
        }
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mood")
        .accessibilityValue(isSet ? "\(Int(value.rounded()))" : "Not set")
    }

    @ViewBuilder
    private var knob: some View {
        if isSet {
            Circle()
                .fill(Color.bgSurface)
                .overlay(Circle().strokeBorder(Color.borderStrong, lineWidth: 1))
                .frame(width: knobSize, height: knobSize)
        } else {
            Circle()
                .strokeBorder(Color.borderStrong, lineWidth: 1.5)
                .background(Circle().fill(Color.bgCanvas))
                .frame(width: knobSize, height: knobSize)
        }
    }
}
