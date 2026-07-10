import DesignSystem
import JarvisAPI
import SwiftUI

/// Habits list (§B3): week-pace header strip, habit cards grouped by area,
/// paused group at the bottom, editor sheet via toolbar +.
struct HabitsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = HabitsStore()
    @State private var detailRoute: HabitDetailRoute?
    @State private var editingHabit: HabitDTO?
    @State private var showNewEditor = false
    @State private var archiveCandidate: HabitDTO?
    @State private var showPaused = false

    var body: some View {
        Group {
            if store.content.value != nil {
                content
            } else if case .failed(let message) = store.content {
                errorState(message)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle("Habits")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New habit")
            }
        }
        .navigationDestination(item: $detailRoute) { route in
            HabitDetailView(
                habitId: route.habitId,
                preloaded: store.content.value?.habits.first(where: { $0.id == route.habitId }),
            )
        }
        .sheet(isPresented: $showNewEditor) {
            HabitEditorView(mode: .create) {
                store.invalidateStats()
            }
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditorView(mode: .edit(habit)) {
                store.invalidateStats(for: habit.id)
            }
        }
        .confirmationDialog(
            "Archive habit?",
            isPresented: Binding(
                get: { archiveCandidate != nil },
                set: { if !$0 { archiveCandidate = nil } },
            ),
            presenting: archiveCandidate,
        ) { habit in
            Button("Archive \(habit.name)", role: .destructive) {
                Task { await store.archive(habit) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The habit stops counting from today. Its history is kept.")
        }
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

    @ViewBuilder
    private var content: some View {
        if store.activeHabits.isEmpty, store.pausedHabits.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if let error = store.mutationError {
                        errorBanner(error)
                    }
                    headerStrip
                    ForEach(store.groupedHabits) { group in
                        SectionHeader(group.title)
                            .padding(.top, Space.xs)
                        ForEach(group.habits) { habit in
                            habitCard(habit)
                        }
                    }
                    pausedGroup
                }
                .padding(PageMargin.standard)
                #if os(macOS)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                #endif
            }
            .refreshable { await store.load() }
        }
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

    // MARK: - Header strip

    private var headerStrip: some View {
        let summary = store.paceSummary
        return HStack(spacing: Space.md) {
            Text("This week · \(summary.onPace) of \(summary.total) habits on pace")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: Space.sm)
            HStack(spacing: Space.xs) {
                ForEach(Array(summary.flags.enumerated()), id: \.offset) { _, onPace in
                    Circle()
                        .fill(onPace ? Color.success : Color.warning)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(Space.md)
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: - Habit card

    private func habitCard(_ habit: HabitDTO) -> some View {
        let entry = store.todayEntry(for: habit.id)
        let stats = store.stats[habit.id]

        return HStack(spacing: Space.md) {
            Image(systemName: HabitDisplay.icon(for: habit))
                .font(.system(size: 16))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 32, height: 32)
                .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Space.sm) {
                    Text(HabitDisplay.typeCaption(for: habit))
                        .font(.subheadJ)
                        .foregroundStyle(Color.textSecondary)
                    if let stats {
                        StreakChip(count: stats.streak.current, unit: stats.streak.unit)
                    }
                }
            }

            Spacer(minLength: Space.sm)

            if let entry {
                habitControl(entry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard(padding: Space.md)
        .contentShape(Rectangle())
        .onTapGesture { detailRoute = HabitDetailRoute(habitId: habit.id) }
        .contextMenu {
            Button("Edit") { editingHabit = habit }
            Button(habit.pausedAt == nil ? "Pause" : "Resume") {
                Task { await store.setPaused(habit, paused: habit.pausedAt == nil) }
            }
            Button("Archive", role: .destructive) { archiveCandidate = habit }
        }
    }

    @ViewBuilder
    private func habitControl(_ entry: HabitTodayEntryDTO) -> some View {
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
                logButton(disabled: entry.repsToday >= entry.habit.targetReps) {
                    Task { await store.logHabit(entry.habit.id) }
                }
            }

        case .weeklyFrequency:
            HStack(spacing: Space.md) {
                PaceCapsule(
                    target: entry.habit.targetReps,
                    done: entry.weekTotal,
                    expectedByTonight: HabitDisplay.expectedByTonight(
                        target: entry.habit.targetReps,
                        dayKey: store.content.value?.today.dayKey ?? DayKeyMath.todayKey(),
                    ),
                    status: HabitDisplay.paceStatus(entry.pace),
                )
                .frame(maxWidth: 180)
                logButton(disabled: false) {
                    Task { await store.logHabit(entry.habit.id) }
                }
            }
        }
    }

    private func logButton(disabled: Bool, action: @escaping () -> Void) -> some View {
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

    // MARK: - Paused group

    @ViewBuilder
    private var pausedGroup: some View {
        if !store.pausedHabits.isEmpty {
            Button {
                withAnimation(.easeOut(duration: 0.25)) { showPaused.toggle() }
            } label: {
                HStack(spacing: Space.xs) {
                    Text("Paused (\(store.pausedHabits.count))")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textTertiary)
                    Image(systemName: showPaused ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, Space.sm)

            if showPaused {
                ForEach(store.pausedHabits) { habit in
                    HStack(spacing: Space.md) {
                        Image(systemName: HabitDisplay.icon(for: habit))
                            .font(.system(size: 15))
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.name)
                                .font(.headlineJ)
                                .foregroundStyle(Color.textTertiary)
                            Text("Paused — not counted in scoring")
                                .font(.captionJ)
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                        Button("Resume") {
                            Task { await store.setPaused(habit, paused: false) }
                        }
                        .buttonStyle(.jarvisGhost)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .jarvisCard(padding: Space.md)
                    .opacity(0.7)
                    .contextMenu {
                        Button("Edit") { editingHabit = habit }
                        Button("Resume") {
                            Task { await store.setPaused(habit, paused: false) }
                        }
                        Button("Archive", role: .destructive) { archiveCandidate = habit }
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("Habits are the engine of your daily score")
                    .font(.title2J)
                    .foregroundStyle(Color.textPrimary)

                VStack(alignment: .leading, spacing: Space.lg) {
                    explainerRow(
                        icon: "checkmark.circle",
                        title: "Daily",
                        detail: "Once a day. A simple check keeps the streak alive.",
                    )
                    explainerRow(
                        icon: "circle.grid.2x1",
                        title: "Multiple per day",
                        detail: "N times a day — partial reps earn partial credit.",
                    )
                    explainerRow(
                        icon: "calendar",
                        title: "Weekly target",
                        detail: "N times a week. Only the weekly total counts — swap days freely.",
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .jarvisCard()

                Button("Create habit") {
                    showNewEditor = true
                }
                .buttonStyle(.jarvisPrimary)
            }
            .padding(PageMargin.standard)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private func explainerRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}
