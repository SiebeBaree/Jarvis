import DesignSystem
import JarvisAPI
import SwiftUI

private struct SessionRoute: Hashable, Identifiable {
    let sessionId: String
    var id: String { sessionId }
}

private struct RoutineRoute: Hashable, Identifiable {
    let routineId: String?
    var id: String { routineId ?? "new" }
}

/// The Train home: what you are doing right now, what you can start, and how
/// the last two months have gone.
///
/// The unfinished-workout card comes first and is the only thing on screen
/// with a filled button, because "I walked into the gym and want to carry on"
/// is by far the most common reason this screen is open.
struct TrainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    let store: WorkoutsStore

    @State private var sessionRoute: SessionRoute?
    @State private var routineRoute: RoutineRoute?
    @State private var startingRoutineId: String?
    @State private var deleteTarget: RoutineSummaryDTO?

    var body: some View {
        List {
            Group {
                if let error = store.actionError {
                    inlineError(error)
                }
                if let active = store.activeSession {
                    continueCard(active)
                }
                routinesSection
                historySection
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
        .background(Color.bgCanvas)
        .refreshable { await store.loadAll(force: true) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New routine", systemImage: "square.stack.3d.up") {
                        routineRoute = RoutineRoute(routineId: nil)
                    }
                    Button("Freeform workout", systemImage: "bolt") {
                        start(routineId: nil, title: "Workout")
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
        }
        .navigationDestination(item: $sessionRoute) { route in
            WorkoutSessionView(sessionId: route.sessionId, store: store)
        }
        .sheet(item: $routineRoute) { route in
            RoutineEditorView(store: store, routineId: route.routineId)
        }
        .confirmationDialog(
            "Delete \"\(deleteTarget?.name ?? "")\"?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } },
            ),
            titleVisibility: .visible,
        ) {
            Button("Delete routine", role: .destructive) {
                if let target = deleteTarget {
                    Task { await store.deleteRoutine(target.id) }
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Workouts you already did are kept.")
        }
        .task {
            store.bind(model)
            await store.loadAll()
        }
        .onChange(of: model.dataRevision) {
            Task { await store.loadAll() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.loadAll() } }
        }
    }

    // MARK: - Continue

    private func continueCard(_ session: SessionSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ItemColor.rose.color)
                Text("In progress")
                    .font(.captionJ)
                    .foregroundStyle(ItemColor.rose.color)
                Spacer(minLength: 0)
                Text(HabitDisplay.shortLabel(for: session.dayKey))
                    .font(.microJ)
                    .foregroundStyle(Color.textTertiary)
            }

            Text(session.title)
                .font(.title2J)
                .foregroundStyle(Color.textPrimary)

            Text(session.setCount == 0
                ? "Nothing logged yet"
                : "\(session.setCount) set\(session.setCount == 1 ? "" : "s") · \(Format.weight(session.volumeKg)) kg lifted")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)

            Button {
                sessionRoute = SessionRoute(sessionId: session.id)
            } label: {
                Text("Continue workout").frame(maxWidth: .infinity)
            }
            .buttonStyle(.jarvisProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .background(
            ItemColor.rose.soft,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous),
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(ItemColor.rose.color.opacity(0.35), lineWidth: 1),
        )
        .padding(.bottom, Space.sm)
    }

    // MARK: - Routines

    @ViewBuilder
    private var routinesSection: some View {
        SectionHeader("Routines", subtitle: routineSubtitle) {
            Button("New") { routineRoute = RoutineRoute(routineId: nil) }
                .buttonStyle(.jarvisSoft)
        }
        .padding(.top, Space.sm)
        .padding(.bottom, Space.xs)

        if store.routineList.isEmpty {
            if case .loading = store.routines {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.xl)
            } else {
                routinesEmpty
            }
        } else {
            ForEach(store.routineList) { routine in
                routineCard(routine)
            }
        }
    }

    private var routineSubtitle: String? {
        store.routineList.isEmpty ? nil : "\(store.routineList.count)"
    }

    private func routineCard(_ routine: RoutineSummaryDTO) -> some View {
        let color = ItemColor.named(routine.colorHex)
        return HStack(spacing: Space.md) {
            if let emoji = routine.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: 22))
                    .frame(width: TileSize.row, height: TileSize.row)
                    .background(color.soft, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            } else {
                IconTile(symbol: "figure.strengthtraining.traditional", color: color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(routineMeta(routine))
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.sm)

            if startingRoutineId == routine.id {
                ProgressView().controlSize(.small).frame(width: 60)
            } else {
                Button("Start") { start(routineId: routine.id, title: routine.name) }
                    .buttonStyle(.jarvisSoft(color.color))
                    .disabled(routine.exerciseCount == 0)
            }
        }
        .frame(minHeight: RowHeight.standard)
        .jarvisRow()
        .contentShape(Rectangle())
        .onTapGesture { routineRoute = RoutineRoute(routineId: routine.id) }
        .contextMenu {
            Button("Edit routine", systemImage: "pencil") {
                routineRoute = RoutineRoute(routineId: routine.id)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteTarget = routine
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteTarget = routine
            }
        }
    }

    private func routineMeta(_ routine: RoutineSummaryDTO) -> String {
        let count = routine.exerciseCount == 0
            ? "No exercises yet"
            : "\(routine.exerciseCount) exercise\(routine.exerciseCount == 1 ? "" : "s")"
        guard let last = routine.lastPerformedDayKey else { return "\(count) · never trained" }
        let today = DayKeyMath.todayKey(boundaryHour: model.settings?.dayBoundaryHour ?? 3)
        let days = DayKeyMath.diffDays(last, today)
        let when = switch days {
        case 0: "today"
        case 1: "yesterday"
        case 2...13: "\(days) days ago"
        default: HabitDisplay.shortLabel(for: last)
        }
        return "\(count) · last \(when)"
    }

    private var routinesEmpty: some View {
        EmptyState(
            symbol: "figure.strengthtraining.traditional",
            title: "Write your first routine",
            message: "A routine is your own list: leg day, chest and back, whatever you actually do. Then every workout shows what you lifted last time.",
            tint: ItemColor.rose.color,
        ) {
            Button("Create a routine") { routineRoute = RoutineRoute(routineId: nil) }
                .buttonStyle(.jarvisPrimary)
        }
    }

    private func start(routineId: String?, title: String?) {
        startingRoutineId = routineId ?? "freeform"
        Task {
            let id = await store.startWorkout(routineId: routineId, title: title)
            startingRoutineId = nil
            if let id {
                Haptics.play(.success)
                sessionRoute = SessionRoute(sessionId: id)
            }
        }
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        let finished = store.sessionList.filter(\.isFinished)
        if !finished.isEmpty {
            SectionHeader("Recent workouts", subtitle: volumeSubtitle(finished))
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xs)

            WeeklyVolumeBars(bars: store.weeklyBars())
                .padding(.bottom, Space.sm)

            ForEach(finished.prefix(12)) { session in
                historyRow(session)
            }
        }
    }

    private func volumeSubtitle(_ sessions: [SessionSummaryDTO]) -> String {
        let today = DayKeyMath.todayKey(boundaryHour: model.settings?.dayBoundaryHour ?? 3)
        let monthAgo = DayKeyMath.addDays(today, -30)
        let recent = sessions.filter { $0.dayKey >= monthAgo }
        return "\(recent.count) in the last 30 days"
    }

    private func historyRow(_ session: SessionSummaryDTO) -> some View {
        HStack(spacing: Space.md) {
            VStack(spacing: 0) {
                Text(HabitDisplay.shortLabel(for: session.dayKey))
                    .font(.microJ)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(sessionMeta(session))
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: Space.sm)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(minHeight: RowHeight.standard)
        .jarvisRow()
        .contentShape(Rectangle())
        .onTapGesture { sessionRoute = SessionRoute(sessionId: session.id) }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                withJarvisAnimation { store.deleteWorkout(session.id) }
            }
        }
    }

    private func sessionMeta(_ session: SessionSummaryDTO) -> String {
        var parts = ["\(session.setCount) sets"]
        if session.volumeKg > 0 { parts.append("\(Format.weight(session.volumeKg)) kg") }
        if let minutes = session.durationMinutes, minutes > 0 { parts.append("\(minutes) min") }
        return parts.joined(separator: " · ")
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: Space.sm) {
            Text(message)
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
            Spacer(minLength: Space.sm)
            Button("Dismiss") { store.actionError = nil }
                .buttonStyle(.plain)
                .font(.subheadJ)
                .foregroundStyle(Color.accentPrimary)
        }
        .padding(Space.md)
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }
}

// MARK: - Weekly bars

/// Eight weeks of training volume. Deliberately unlabelled and small: it is a
/// glance ("am I still going?"), not a chart to read numbers off.
struct WeeklyVolumeBars: View {
    let bars: [WorkoutsStore.WeekBar]

    private var peak: Double {
        max(bars.map(\.volumeKg).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .bottom, spacing: Space.xs) {
                ForEach(bars) { bar in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(bar.sessions == 0 ? Color.bgSubtle : ItemColor.rose.color.opacity(0.85))
                            .frame(height: max(3, 46 * bar.volumeKg / peak))
                        Text("\(bar.sessions)")
                            .font(.microJ)
                            .foregroundStyle(bar.sessions == 0 ? Color.textTertiary : Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "Week of \(HabitDisplay.shortLabel(for: bar.weekStart)): \(bar.sessions) workouts",
                    )
                }
            }
            .frame(height: 64, alignment: .bottom)

            Text("Workouts per week, last \(bars.count) weeks")
                .font(.microJ)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard(padding: Space.md)
    }
}

/// Weight and set formatting, shared across the training screens so a set
/// reads identically in the logger, the "last time" line and the history.
enum Format {
    /// Drops the decimal when there is nothing after it: "82.5" but "80".
    static func weight(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }

    /// "80 × 8", or "12 reps" for bodyweight work that carries no load.
    static func set(_ set: WorkoutSetDTO) -> String {
        let reps = set.reps.map(String.init) ?? "-"
        guard let load = set.weightKg, load > 0 else { return "\(reps) reps" }
        return "\(weight(load)) × \(reps)"
    }

    /// "80 × 8, 80 × 7" — a whole session's work on one movement.
    static func sets(_ sets: [WorkoutSetDTO]) -> String {
        sets.map(set).joined(separator: ", ")
    }
}
