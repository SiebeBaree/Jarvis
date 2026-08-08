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
    @Environment(\.openSettings) private var openSettings

    @State private var store = TodayStore()
    @State private var selectedDay: DayKey?
    @State private var showBreakdown = false
    /// Tapping a habit on Today opens its detail. It used to do nothing here,
    /// so seeing a streak meant leaving for the Habits tab and finding it again.
    @State private var habitRoute: HabitDetailRoute?
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
        #if os(iOS)
        // A large title spent ~90pt restating what the tab bar already says,
        // on the one screen where vertical space is the scarce resource.
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            // Settings lives in the sidebar on macOS; only iPhone needs the
            // gear. Trends, Body and Improve used to hang off this toolbar as
            // unlabelled glyphs — they are segments of the Progress tab now.
            #if os(iOS)
            ToolbarItem(placement: .navigation) {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
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
        .navigationDestination(item: $habitRoute) { route in
            HabitDetailView(habitId: route.habitId)
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
        Group {
            #if os(iOS)
            // The strip is the stable frame the pages swipe behind, so on a
            // phone it stays put above them. (No toolbar band to worry about
            // here — that is a macOS problem, handled in `dayContent`.)
            VStack(spacing: 0) {
                dayStrip
                    .padding(.horizontal, PageMargin.standard)
                    .padding(.bottom, Space.sm)
                    // Opaque, or the page scrolling underneath shows straight
                    // through the strip and section titles appear to pass
                    // behind the pills.
                    .background(Color.bgCanvas)
                    .zIndex(1)
                pages
            }
            #else
            pages
            #endif
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

    /// Day strip. It is the FIRST ROW OF THE PAGE, not a bar above it: fixed
    /// content at the top edge makes the macOS window toolbar paint its
    /// permanent opaque band, and four full-width two-line buttons were a lot
    /// of chrome to carry on a screen you open twenty times a day. Four small
    /// capsules instead — day, score, and an amber dot on a day still missing
    /// its feel score, which is the entire reason you would go back at all.
    private var dayStrip: some View {
        HStack(spacing: Space.xs) {
            ForEach(store.reachableDayKeys.reversed(), id: \.self) { dayKey in
                dayCapsule(dayKey)
            }
            Spacer(minLength: 0)
        }
    }

    private func dayCapsule(_ dayKey: DayKey) -> some View {
        let isSelected = dayKey == visibleDayKey
        let isToday = dayKey == store.payload?.dayKey
        // Today is unrated until the evening — a warning dot on it all day
        // would just be wallpaper.
        let needsRating = !isToday && store.payload(for: dayKey).map { $0.mood == nil } == true

        return Button {
            Haptics.play(.light)
            withJarvisAnimation(Motion.quick) { selectedDay = dayKey }
        } label: {
            HStack(spacing: 5) {
                Text(dayLabel(dayKey))
                    .font(.captionJ)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textTertiary)
                Text(scoreLabel(dayKey))
                    .font(.monoJ)
                    .foregroundStyle(isSelected ? Color.accentPrimary : Color.textTertiary)
                if needsRating {
                    Circle()
                        .fill(Color.warning)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.bgSurface)
                        .jarvisShadow(.card)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .jarvisAnimation(Motion.quick, value: isSelected)
        .accessibilityLabel(
            "\(dayLabel(dayKey)), score \(scoreLabel(dayKey))\(needsRating ? ", not rated" : "")",
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Short enough for a capsule: "Today", "Yest", "Sun".
    private func dayLabel(_ dayKey: DayKey) -> String {
        guard let today = store.payload?.dayKey else { return dayKey }
        let label = DayKeyMath.relativeLabel(for: dayKey, today: today)
        switch label {
        case "Today": return label
        case "Yesterday": return "Yest"
        default: return String(label.prefix(3))
        }
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
                #if os(macOS)
                // Inside the List, because fixed content at the top edge makes
                // the window toolbar paint its permanent opaque band.
                dayStrip
                #endif
                if let error = store.mutationError, isToday {
                    errorBanner(error)
                }
                scoreHeader(payload, isToday: isToday)
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
                Color.clear.frame(height: Space.xxxl)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: 3, leading: PageMargin.standard,
                bottom: 3, trailing: PageMargin.standard,
            ))
            #if os(macOS)
            .frame(maxWidth: PageMargin.contentMaxWidth)
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

    private func weekdayName(_ dayKey: String) -> String {
        guard let date = DayKeyMath.date(from: dayKey) else { return "today" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// "Sat 8 Aug" — short enough to live inside the ring.
    private func ringCaption(_ dayKey: DayKey, isToday: Bool) -> String {
        guard let date = DayKeyMath.date(from: dayKey) else { return dayKey }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    // MARK: - Score card

    private var weights: (tasks: Double, habits: Double, feel: Double) {
        guard let w = model.settings?.scoreWeights else { return (40, 40, 20) }
        return (w.tasks, w.habits, w.feel)
    }

    /// Ring plus the three component bars. The date lives inside the ring
    /// rather than on a line of its own above the card — a whole row spent on
    /// "Saturday, August 8" is a row not spent on the day's actual contents.
    private func scoreHeader(_ payload: DayPayload, isToday: Bool) -> some View {
        let score = payload.score
        let w = weights
        let feelFill = score.feelPoints.map { $0 / max(w.feel, 1) }

        return VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.lg) {
                ScoreRing(
                    size: 116,
                    total: score.total,
                    caption: ringCaption(payload.dayKey, isToday: isToday),
                )
                VStack(alignment: .leading, spacing: Space.md) {
                    ComponentBar(
                        label: "Tasks",
                        points: score.taskPoints,
                        weight: w.tasks,
                        tint: .accentPrimary,
                    )
                    ComponentBar(
                        label: "Habits",
                        points: score.habitPoints,
                        weight: w.habits,
                        tint: .success,
                    )
                    ComponentBar(
                        label: "Feel",
                        points: score.feelPoints,
                        weight: w.feel,
                        tint: .warning.mix(with: .success, by: feelFill ?? 0),
                    )
                }
            }
            contextCaption(payload, isToday: isToday)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .pressable(scale: 0.985) { showBreakdown = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Shows the score breakdown"))
    }

    /// The two things that need saying about *which* day you are looking at,
    /// shown only when they apply.
    @ViewBuilder
    private func contextCaption(_ payload: DayPayload, isToday: Bool) -> some View {
        if isToday, DayKeyMath.isLateNight() {
            captionRow(
                symbol: "moon.stars",
                text: "Late night — still counts for \(weekdayName(payload.dayKey))",
            )
        } else if !isToday {
            captionRow(
                symbol: "arrow.uturn.backward",
                text: "Catching up — feel and habits are still editable.",
            )
        }
    }

    private func captionRow(symbol: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(text).font(.microJ)
        }
        .foregroundStyle(Color.textTertiary)
    }

    static func formatPoints(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }

    // MARK: - Overdue

    @ViewBuilder
    private func overdueSection(_ payload: DayPayload) -> some View {
        if !payload.overdueTasks.isEmpty {
            SectionHeader(
                "Overdue",
                subtitle: "\(payload.overdueTasks.count) still open",
            )
            .padding(.top, Space.lg)
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

        SectionHeader("Tasks", subtitle: taskSubtitle(payload))
            .padding(.top, Space.lg)

        if payload.tasksDue.isEmpty, payload.overdueTasks.isEmpty {
            if payload.habits.isEmpty, isToday {
                heroEmptyState
            } else {
                quietLine(isToday ? "Nothing scheduled today" : "Nothing was scheduled")
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

    /// "3 of 7 done" — the one number that says whether the day is going well,
    /// without having to count rows.
    private func taskSubtitle(_ payload: DayPayload) -> String? {
        let all = payload.tasksDue
        guard !all.isEmpty else { return nil }
        let done = all.filter { $0.status == .done }.count
        return "\(done) of \(all.count) done"
    }

    private func quietLine(_ text: String) -> some View {
        Text(text)
            .font(.bodyJ)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.sm)
    }

    private var heroEmptyState: some View {
        EmptyState(
            symbol: "sparkles",
            title: "A clean slate",
            message: "Add a task for today, or set up the habits you want to keep.",
        ) {
            HStack(spacing: Space.sm) {
                Button("Add a task") { composerActive = true }
                    .buttonStyle(.jarvisPrimary)
                Button("Set up habits") { model.requestedSection = .habits }
                    .buttonStyle(.jarvisSecondary)
            }
        }
    }

    // MARK: - Habits

    @ViewBuilder
    private func habitsSection(_ payload: DayPayload, isToday: Bool) -> some View {
        let alsoAvailable = payload.habits.filter { isAlsoAvailable($0) }
        let active = payload.habits.filter { !isAlsoAvailable($0) }
        let done = payload.habits.filter { isSatisfied($0) }.count

        SectionHeader(
            "Habits",
            subtitle: payload.habits.isEmpty ? nil : "\(done) of \(payload.habits.count) done",
        )
        .padding(.top, Space.lg)

        if payload.habits.isEmpty, !payload.tasksDue.isEmpty || !payload.overdueTasks.isEmpty {
            HStack(spacing: Space.sm) {
                quietLine("No habits yet")
                Button("Set up habits") { model.requestedSection = .habits }
                    .buttonStyle(.jarvisSoft)
            }
        }

        // Each habit is its own card rather than a row in a shared list: it
        // makes the control feel like an object you press, and it is what
        // separates a tracker you enjoy tapping from a spreadsheet.
        ForEach(active) { entry in
            habitCard(entry, payload: payload, isToday: isToday, isMuted: false)
        }

        if !alsoAvailable.isEmpty {
            CaptionLabel("Also available")
                .padding(.top, Space.sm)
        }

        // Weekly habits not planned for today. Logging one promotes it — the
        // day-swap mechanic, and the reason this group is loggable rather
        // than merely informational.
        ForEach(alsoAvailable) { entry in
            habitCard(entry, payload: payload, isToday: isToday, isMuted: true)
        }
    }

    private func isAlsoAvailable(_ entry: HabitTodayEntryDTO) -> Bool {
        entry.habit.type == .weeklyFrequency && !entry.plannedToday && entry.repsToday == 0
    }

    private func isSatisfied(_ entry: HabitTodayEntryDTO) -> Bool {
        switch entry.habit.type {
        case .daily, .multiDaily: entry.repsToday >= entry.habit.targetReps
        case .weeklyFrequency: entry.weekTotal >= entry.habit.targetReps
        }
    }

    private func habitCard(
        _ entry: HabitTodayEntryDTO,
        payload: DayPayload,
        isToday: Bool,
        isMuted: Bool,
    ) -> some View {
        HabitRow(
            entry: entry,
            dayKey: payload.dayKey,
            isMuted: isMuted,
            onLog: { store.logHabit(entry.habit.id, dayKey: payload.dayKey) },
            onUnlog: { store.unlogHabit(entry.habit.id, dayKey: payload.dayKey) },
            onOpen: { habitRoute = HabitDetailRoute(habitId: entry.habit.id) },
        )
        .padding(.horizontal, Space.md)
        .background(
            Color.bgSurface,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous),
        )
        .jarvisShadow(.card)
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
