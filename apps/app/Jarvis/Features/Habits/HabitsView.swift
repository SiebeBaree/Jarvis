import DesignSystem
import JarvisAPI
import SwiftUI

/// The Habits tab: compose at the top, habit cards below, paused ones tucked
/// away at the bottom.
///
/// One List owns the whole page, with the composer as its first scrolling row
/// — fixed content at a macOS window's top edge makes the toolbar paint its
/// permanent opaque band.
struct HabitsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = HabitsStore()
    @State private var detailRoute: HabitDetailRoute?
    @State private var editingHabit: HabitDTO?
    @State private var editorDraft: HabitDraft?
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $detailRoute) { route in
            HabitDetailView(
                habitId: route.habitId,
                preloaded: store.content.value?.habits.first(where: { $0.id == route.habitId }),
            )
        }
        .sheet(item: $editorDraft) { draft in
            HabitEditorView(mode: .create(draft), store: store) {
                store.invalidateStats()
            }
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditorView(mode: .edit(habit), store: store) {
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
                store.archive(habit)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The habit stops counting from today. Its history is kept.")
        }
        .task {
            store.configure(model)
            Haptics.prepare()
            await store.load()
        }
        .onChange(of: model.dataRevision) {
            Task { await store.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.load() }
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        List {
            Group {
                quickAdd
                if let error = store.mutationError {
                    errorBanner(error)
                }
                if store.activeHabits.isEmpty, store.pausedHabits.isEmpty {
                    emptyState
                } else {
                    paceLine
                }

                // One flat, ordered list of rows across all groups. Group
                // headers are emitted inline rather than nesting a ForEach in
                // a ForEach, so every row keeps a stable identity and removing
                // one animates the row that actually left.
                ForEach(rowItems) { item in
                    switch item.kind {
                    case .header(let title):
                        CaptionLabel(title)
                            .padding(.top, Space.md)
                    case .habit(let habit):
                        habitCard(habit)
                    }
                }

                pausedToggle
                ForEach(showPaused ? store.pausedHabits : []) { habit in
                    pausedCard(habit)
                }
                Color.clear.frame(height: Space.xxxl)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: 4, leading: PageMargin.standard,
                bottom: 4, trailing: PageMargin.standard,
            ))
            #if os(macOS)
            .frame(maxWidth: PageMargin.contentMaxWidth)
            .frame(maxWidth: .infinity)
            #endif
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.load(force: true) }
    }

    private var quickAdd: some View {
        HabitQuickAdd(
            nextColorHex: store.nextColorHex(),
            onCreate: { store.create($0) },
            onOpenEditor: { editorDraft = $0 },
        )
        .padding(.top, Space.xs)
        .padding(.bottom, Space.sm)
    }

    /// A group header is only worth a row when there is more than one group —
    /// "General" above every habit you own is pure noise.
    private struct RowItem: Identifiable {
        enum Kind {
            case header(String)
            case habit(HabitDTO)
        }

        let id: String
        let kind: Kind
    }

    private var rowItems: [RowItem] {
        let groups = store.groupedHabits
        guard groups.count > 1 else {
            return (groups.first?.habits ?? []).map { RowItem(id: $0.id, kind: .habit($0)) }
        }
        return groups.flatMap { group in
            [RowItem(id: "header-\(group.id)", kind: .header(group.title))]
                + group.habits.map { RowItem(id: $0.id, kind: .habit($0)) }
        }
    }

    private var paceLine: some View {
        let summary = store.paceSummary
        return HStack(spacing: Space.sm) {
            Text("This week")
                .font(.subheadStrongJ)
                .foregroundStyle(Color.textSecondary)
            Text("\(summary.onPace) of \(summary.total) on pace")
                .font(.subheadJ)
                .foregroundStyle(Color.textTertiary)
            Spacer(minLength: Space.sm)
            HStack(spacing: 3) {
                ForEach(Array(summary.flags.enumerated()), id: \.offset) { _, onPace in
                    Capsule()
                        .fill(onPace ? Color.success : Color.bgSubtle)
                        .frame(width: 12, height: 4)
                }
            }
        }
        .padding(.top, Space.xs)
        .padding(.bottom, Space.xs)
    }

    // MARK: - Cards

    @ViewBuilder
    private func habitCard(_ habit: HabitDTO) -> some View {
        let entry = store.todayEntry(for: habit.id)

        VStack(alignment: .leading, spacing: Space.sm) {
            if let entry {
                HabitRow(
                    entry: entry,
                    dayKey: store.content.value?.today.dayKey ?? DayKeyMath.todayKey(),
                    streak: store.stats[habit.id]?.streak,
                    onLog: { store.logHabit(habit.id) },
                    onUnlog: { store.unlogHabit(habit.id) },
                    onOpen: { detailRoute = HabitDetailRoute(habitId: habit.id) },
                )
                if let recentDays = entry.recentDays, !recentDays.isEmpty {
                    Divider().overlay(Color.borderHairline)
                    RecentDaysStrip(entry: entry, recentDays: recentDays, store: store)
                        .padding(.bottom, Space.xs)
                }
            } else {
                // A habit created moments ago, before Today's payload has
                // caught up. It still renders — it just has nothing to log yet.
                HStack(spacing: Space.md) {
                    IconTile(
                        symbol: HabitDisplay.icon(for: habit),
                        color: HabitDisplay.color(for: habit),
                    )
                    Text(habit.name).font(.headlineJ).foregroundStyle(Color.textPrimary)
                    Spacer()
                }
                .frame(minHeight: RowHeight.standard)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .jarvisShadow(.card)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editingHabit = habit }
            Button(habit.pausedAt == nil ? "Pause" : "Resume", systemImage: "pause") {
                store.setPaused(habit, paused: habit.pausedAt == nil)
            }
            Button("Archive", systemImage: "archivebox", role: .destructive) {
                archiveCandidate = habit
            }
        }
    }

    private func pausedCard(_ habit: HabitDTO) -> some View {
        HStack(spacing: Space.md) {
            IconTile(
                symbol: HabitDisplay.icon(for: habit),
                color: HabitDisplay.color(for: habit),
                isMuted: true,
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textSecondary)
                Text("Not counted in scoring")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: Space.sm)
            Button("Resume") { store.setPaused(habit, paused: false) }
                .buttonStyle(.jarvisSoft)
        }
        .padding(.horizontal, Space.md)
        .frame(minHeight: RowHeight.standard)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editingHabit = habit }
            Button("Resume", systemImage: "play") { store.setPaused(habit, paused: false) }
            Button("Archive", systemImage: "archivebox", role: .destructive) {
                archiveCandidate = habit
            }
        }
    }

    @ViewBuilder
    private var pausedToggle: some View {
        if !store.pausedHabits.isEmpty {
            Button {
                withJarvisAnimation(Motion.smooth) { showPaused.toggle() }
            } label: {
                HStack(spacing: Space.xs) {
                    Text("Paused (\(store.pausedHabits.count))")
                        .font(.subheadStrongJ)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(showPaused ? 90 : 0))
                }
                .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, Space.lg)
        }
    }

    // MARK: - States

    private var emptyState: some View {
        EmptyState(
            symbol: "repeat",
            title: "No habits yet",
            message: "Type a name above and press return. Daily by default. Tap the chips to make it several times a day, or a weekly target.",
            tint: ItemColor.violet.color,
        )
    }

    private func errorState(_ message: String) -> some View {
        EmptyState(
            symbol: "exclamationmark.triangle",
            title: "Could not load habits",
            message: message,
            tint: .warning,
        ) {
            Button("Try again") { Task { await store.load(force: true) } }
                .buttonStyle(.jarvisPrimary)
        }
        .frame(maxHeight: .infinity)
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
            .buttonStyle(.jarvisSoft)
        }
        .padding(Space.md)
        .background(Color.warningSubtle, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }
}
