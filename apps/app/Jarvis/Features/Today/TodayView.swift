import DesignSystem
import JarvisAPI
import SwiftUI

/// The Today screen: score header, feel score, tasks, habits — for today and
/// the three days behind it.
///
/// The back-days are the point of the horizontal pager: the day you forgot to
/// rate is still there tomorrow, so a missed evening doesn't turn into a
/// permanent hole in the record. Past pages are read-only for tasks (they are
/// already scored) but fully editable for the feel score and habit reps.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = TodayStore()
    @State private var selectedDay: DayKey?
    @State private var showSettings = false
    @State private var showBreakdown = false
    /// Quick-add composer state (today's page only).
    @State private var composerActive = false
    @State private var editorDraft: TaskDraft?

    var body: some View {
        Group {
            if store.payload != nil {
                pager
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
                    Image(systemName: "figure.stand")
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
            if let payload = visiblePayload {
                ScoreBreakdownSheet(payload: payload)
            }
        }
        .sheet(item: $editorDraft) { draft in
            TaskEditorView(draft: draft) { request in
                store.createTask(request)
            }
        }
        .task {
            store.configure(model)
            await store.load()
            store.prefetchReachableDays()
        }
        .task {
            // Quick-add's category chip reads these; loading them here means
            // the composer never has to wait on a fetch when it opens.
            await model.loadCategories()
        }
        .onChange(of: model.dataRevision) {
            Task {
                await store.load()
                // Past pages are memory-only, so a landed write has to push
                // them explicitly or they keep showing pre-write numbers.
                store.prefetchReachableDays(force: true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.load() }
            }
        }
        .onChange(of: store.payload?.dayKey) { _, today in
            // Midnight rollover (or first load) — snap back to today.
            if let today { selectedDay = today }
        }
    }

    // MARK: - Day pager

    private var visibleDayKey: DayKey? {
        selectedDay ?? store.payload?.dayKey
    }

    private var visiblePayload: DayPayload? {
        visibleDayKey.flatMap { store.payload(for: $0) }
    }

    private var pager: some View {
        VStack(spacing: 0) {
            dayPicker
            pages
        }
        .onChange(of: visibleDayKey) { _, dayKey in
            guard let dayKey else { return }
            Task { await store.loadPast(dayKey) }
        }
    }

    @ViewBuilder
    private var pages: some View {
        #if os(iOS)
        // Swiping between days is the native gesture on a phone.
        TabView(selection: Binding(get: { visibleDayKey ?? "" }, set: { selectedDay = $0 })) {
            ForEach(store.reachableDayKeys, id: \.self) { dayKey in
                dayPage(dayKey)
                    .tag(dayKey)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        // A Mac has no swipe-between-pages idiom, and TabView without the page
        // style draws an actual tab bar — a row of unlabelled buttons under the
        // day strip that already does this job. So: render the selected day,
        // switch it from the strip or ⌘←/⌘→.
        if let dayKey = visibleDayKey {
            dayPage(dayKey)
                .id(dayKey)
                .transition(.opacity)
                .background(dayShortcuts)
        }
        #endif
    }

    #if os(macOS)
    /// ⌘← / ⌘→ step through the reachable days.
    private var dayShortcuts: some View {
        Group {
            Button("Previous day") { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Next day") { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
        }
        .hidden()
    }

    /// `direction` is in calendar terms: -1 goes back in time.
    private func step(_ direction: Int) {
        let days = store.reachableDayKeys // today first, oldest last
        guard let current = visibleDayKey, let index = days.firstIndex(of: current) else { return }
        let next = index - direction
        guard days.indices.contains(next) else { return }
        withAnimation(.easeOut(duration: 0.15)) { selectedDay = days[next] }
    }
    #endif

    /// Segmented day strip above the pages. It doubles as the affordance —
    /// a horizontal swipe is invisible until something tells you it exists.
    private var dayPicker: some View {
        HStack(spacing: Space.xs) {
            ForEach(store.reachableDayKeys.reversed(), id: \.self) { dayKey in
                let isSelected = dayKey == visibleDayKey
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selectedDay = dayKey }
                } label: {
                    VStack(spacing: 1) {
                        Text(dayLabel(dayKey))
                            .font(.captionJ)
                        Text(scoreLabel(dayKey))
                            .font(.monoJ)
                            .monospacedDigit()
                    }
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.xs)
                    .background(
                        isSelected ? Color.bgSurface : Color.clear,
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous),
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(isSelected ? Color.borderHairline : .clear, lineWidth: 0.5),
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(dayLabel(dayKey)), score \(scoreLabel(dayKey))")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, PageMargin.standard)
        .padding(.bottom, Space.xs)
    }

    private func dayLabel(_ dayKey: DayKey) -> String {
        guard let today = store.payload?.dayKey else { return dayKey }
        let label = DayKeyMath.relativeLabel(for: dayKey, today: today)
        // Weekday names are too wide for a four-up strip on an iPhone.
        return label.count > 9 ? String(label.prefix(3)) : label
    }

    private func scoreLabel(_ dayKey: DayKey) -> String {
        guard let total = store.payload(for: dayKey)?.score.total else { return "—" }
        return "\(Int(total.rounded()))"
    }

    // MARK: - One day

    @ViewBuilder
    private func dayPage(_ dayKey: DayKey) -> some View {
        let isToday = dayKey == store.payload?.dayKey
        switch store.state(for: dayKey) {
        case .loaded(let payload):
            dayContent(payload, isToday: isToday)
        case .failed(let message):
            errorState(message)
        default:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dayContent(_ payload: DayPayload, isToday: Bool) -> some View {
        List {
            Group {
                dateHeader(payload, isToday: isToday)
                if let error = store.mutationError, isToday {
                    errorBanner(error)
                }
                scoreHeader(payload)
                MoodCard(
                    dayKey: payload.dayKey,
                    mood: payload.mood,
                    isToday: isToday,
                    onCommit: { store.setMood($0, on: payload.dayKey) },
                )
                if isToday {
                    CheckinPromptCard() // weekly improvement-area photo prompt
                }
                // Every task/habit ForEach below sits at a FIXED position in
                // this builder (empty collections render nothing) — wrapping
                // one in an `if` makes List fall back to structural row
                // identity, and completing a row then animates its neighbour
                // out instead of the row itself.
                overdueSection(payload)
                tasksSection(payload, isToday: isToday)
                habitsSection(payload, isToday: isToday)
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
        .refreshable {
            if isToday {
                await store.load(force: true)
            } else {
                await store.loadPast(payload.dayKey, force: true)
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Space.lg) {
            Text(message)
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await store.load(force: true) }
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
                Task { await store.load(force: true) }
            }
            .buttonStyle(.plain)
            .font(.subheadJ)
            .foregroundStyle(Color.accentPrimary)
        }
        .padding(Space.md)
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: - Date header

    private func dateHeader(_ payload: DayPayload, isToday: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DayKeyMath.longLabel(for: payload.dayKey))
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
            if isToday, DayKeyMath.isLateNight() {
                Text("Late night — still counts for \(weekdayName(payload.dayKey))")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }
            if !isToday {
                Text("Catching up — the feel score and habits are still editable.")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func weekdayName(_ dayKey: String) -> String {
        guard let date = DayKeyMath.date(from: dayKey) else { return "today" }
        return date.formatted(.dateTime.weekday(.wide))
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

    // MARK: - Overdue

    @ViewBuilder
    private func overdueSection(_ payload: DayPayload) -> some View {
        if !payload.overdueTasks.isEmpty {
            Text("OVERDUE")
                .font(.captionJ)
                .tracking(0.6)
                .foregroundStyle(Color.warning)
                .padding(.top, Space.sm)
        }

        ForEach(payload.overdueTasks) { task in
            TaskRow(
                task: task,
                overdueLabel: task.dueDate.map { "was due \(HabitDisplay.shortLabel(for: $0))" },
                onToggle: { store.completeTask(task) },
                onTap: {},
            )
            .swipeActions(edge: .trailing) {
                Button("Complete") { store.completeTask(task) }
                    .tint(.success)
            }
            .swipeActions(edge: .leading) {
                Button("Today") { store.rescheduleTask(task, to: payload.dayKey) }
                    .tint(.accentPrimary)
                Button("Tomorrow") {
                    store.rescheduleTask(task, to: DayKeyMath.addDays(payload.dayKey, 1))
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
    private func tasksSection(_ payload: DayPayload, isToday: Bool) -> some View {
        let open = sortedOpenTasks(payload)
        let completed = payload.tasksDue.filter { $0.status == .done }

        SectionHeader("Tasks")
            .padding(.top, Space.sm)

        if payload.tasksDue.isEmpty, payload.overdueTasks.isEmpty {
            if payload.habits.isEmpty, isToday {
                heroEmptyState
            } else {
                Text(isToday ? "Nothing scheduled today" : "Nothing was scheduled")
                    .font(.bodyJ)
                    .foregroundStyle(Color.textTertiary)
            }
        }

        // Past days are read-only for tasks: they have already been scored,
        // and back-dating completions would rewrite history rather than
        // record it.
        ForEach(open) { task in
            TaskRow(
                task: task,
                onToggle: { if isToday { store.completeTask(task) } },
                onTap: {},
            )
            .disabled(!isToday)
        }

        if isToday {
            QuickAddComposer(
                todayKey: payload.dayKey,
                categories: model.categories,
                defaults: TaskDraft(dueDate: payload.dayKey),
                isActive: $composerActive,
                onCreate: { store.createTask($0) },
                onCreateCategory: { await model.createCategory(name: $0) },
                onOpenEditor: { editorDraft = $0 },
            )
        }

        ForEach(completed) { task in
            TaskRow(
                task: task,
                onToggle: { if isToday { store.uncompleteTask(task) } },
                onTap: {},
            )
            .disabled(!isToday)
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
    private func habitsSection(_ payload: DayPayload, isToday: Bool) -> some View {
        SectionHeader("Habits")
            .padding(.top, Space.sm)

        let alsoAvailable = payload.habits.filter { isAlsoAvailable($0) }
        let active = payload.habits.filter { !isAlsoAvailable($0) }

        if payload.habits.isEmpty, !payload.tasksDue.isEmpty || !payload.overdueTasks.isEmpty {
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

        ForEach(active) { entry in
            habitRow(entry, payload: payload, subdued: false, isToday: isToday)
        }

        if !alsoAvailable.isEmpty {
            Text("ALSO AVAILABLE")
                .font(.captionJ)
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
                .padding(.top, Space.xs)
        }

        ForEach(alsoAvailable) { entry in
            habitRow(entry, payload: payload, subdued: true, isToday: isToday)
        }
    }

    private func isAlsoAvailable(_ entry: HabitTodayEntryDTO) -> Bool {
        entry.habit.type == .weeklyFrequency && !entry.plannedToday && entry.repsToday == 0
    }

    private func habitRow(
        _ entry: HabitTodayEntryDTO,
        payload: DayPayload,
        subdued: Bool,
        isToday: Bool,
    ) -> some View {
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

            habitControl(entry, payload: payload, isToday: isToday)
        }
        .frame(minHeight: RowHeight.standard)
        .contextMenu {
            Button("Undo last") {
                store.unlogHabit(entry.habit.id, dayKey: payload.dayKey)
            }
            .disabled(entry.repsToday == 0)
        }
    }

    @ViewBuilder
    private func habitControl(_ entry: HabitTodayEntryDTO, payload: DayPayload, isToday: Bool) -> some View {
        let dayKey = payload.dayKey
        switch entry.habit.type {
        case .daily:
            Button {
                if entry.repsToday > 0 {
                    store.unlogHabit(entry.habit.id, dayKey: dayKey)
                } else {
                    store.logHabit(entry.habit.id, dayKey: dayKey)
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
                    action: { store.logHabit(entry.habit.id, dayKey: dayKey) },
                )
                .contextMenu {
                    Button("Undo last") {
                        store.unlogHabit(entry.habit.id, dayKey: dayKey)
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
                        dayKey: dayKey,
                    ),
                    // A past day's pace is settled, so use the week total
                    // rather than the "are you behind right now" wording.
                    status: isToday
                        ? HabitDisplay.paceStatus(entry.pace)
                        : HabitDisplay.weeklyStatus(
                            total: entry.weekTotal,
                            target: entry.habit.targetReps,
                            dayKey: dayKey,
                        ),
                )
                .frame(maxWidth: 190)
                logCapsuleButton(
                    disabled: false,
                    action: { store.logHabit(entry.habit.id, dayKey: dayKey) },
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

/// "How do you feel?" — compact gradient slider (0–100). One caption line
/// with a live word label, then a slim track. Unset = hollow knob, "—" for
/// the value, faint accent card tint. Commits on release (a tap counts).
///
/// Identical on today and on a back-day: rating a day you missed is the
/// reason the pager exists.
private struct MoodCard: View {
    let dayKey: DayKey
    let mood: MoodDTO?
    let isToday: Bool
    let onCommit: (Int) -> Void

    @State private var value: Double = 50
    @State private var isDragging = false

    private var isSet: Bool { mood != nil || isDragging }

    /// Word for the current position — more readable at a glance than "72".
    private var label: String {
        switch value {
        case ..<20: "Rough"
        case ..<40: "Low"
        case ..<60: "Okay"
        case ..<80: "Good"
        default: "Great"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Text(isToday ? "How do you feel?" : "How did you feel?")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                Spacer(minLength: Space.sm)
                Text(isSet ? label : "Not set")
                    .font(.subheadJ)
                    .foregroundStyle(isSet ? Color.textPrimary : Color.textTertiary)
                Text(isSet ? "\(Int(value.rounded()))" : "—")
                    .font(.monoJ)
                    .foregroundStyle(isSet ? Color.textSecondary : Color.textTertiary)
                    .frame(minWidth: 22, alignment: .trailing)
                    .monospacedDigit()
            }
            MoodSlider(value: $value, isSet: isSet, isDragging: $isDragging, onCommit: onCommit)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(
            mood == nil ? Color.accentSubtle.opacity(0.45) : Color.bgSurface,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous),
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.borderHairline, lineWidth: 0.5),
        )
        // Keyed on dayKey: swiping to another page reuses this view, and
        // without the reset the previous day's number would linger on the
        // knob until the payload arrived.
        .onChange(of: dayKey, initial: true) {
            value = Double(mood?.value ?? 50)
        }
        .onChange(of: mood?.value) { _, newValue in
            if let newValue, !isDragging { value = Double(newValue) }
        }
    }
}

/// Custom 0–100 slider over the mood gradient. `Slider` can't tint its track
/// with a gradient cross-platform, so this draws its own track + knob.
struct MoodSlider: View {
    @Binding var value: Double
    var isSet: Bool
    @Binding var isDragging: Bool
    let onCommit: (Int) -> Void

    private let knobSize: CGFloat = 16
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let usable = max(proxy.size.width - knobSize, 1)
            let knobX = CGFloat(value / 100) * usable

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient.moodGradient)
                    .frame(height: trackHeight)
                    .opacity(isSet ? 1 : 0.3)
                    .padding(.horizontal, knobSize / 2)

                knob
                    .scaleEffect(isDragging ? 1.25 : 1)
                    .animation(.spring(duration: 0.2), value: isDragging)
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
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mood")
        .accessibilityValue(isSet ? "\(Int(value.rounded()))" : "Not set")
    }

    private var knob: some View {
        Circle()
            .fill(isSet ? Color.bgSurface : Color.bgCanvas)
            .overlay(Circle().strokeBorder(Color.borderStrong, lineWidth: isSet ? 1 : 1.5))
            .shadow(color: .black.opacity(isSet ? 0.12 : 0), radius: 1.5, y: 0.5)
            .frame(width: knobSize, height: knobSize)
    }
}
