import DesignSystem
import JarvisAPI
import SwiftUI

/// Goal Detail (§B3): title/area/description → progress + manual override →
/// tactics by week (12-cell rows, toggleable past/current cells) → linked
/// habits → linked tasks. Overflow: Mark done / Abandon.
struct GoalDetailView: View {
    let store: PlanStore
    let goalId: String
    /// Snapshot fallback while the store refetches.
    let initialGoal: GoalWithProgressDTO?

    @Environment(AppModel.self) private var model

    @State private var linkedHabits: LoadState<[HabitDTO]> = .idle
    @State private var linkedTasks: LoadState<[TaskDTO]> = .idle
    @State private var showDescriptionEditor = false
    @State private var showAddTactic = false
    @State private var showAbandonConfirm = false
    @State private var manualEnabled = false
    @State private var manualValue: Double = 0
    @State private var deleteCandidate: TacticDTO?

    private var goal: GoalWithProgressDTO? {
        store.goal(id: goalId) ?? initialGoal
    }

    private var currentWeek: Int? { store.currentWeekNumber }
    private var isInactive: Bool { goal.map { $0.status != "active" } ?? false }

    var body: some View {
        Group {
            if let goal {
                content(goal)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle("Goal")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Mark done") {
                        Task {
                            await store.patchGoal(id: goalId, [
                                "trackStatus": .string("done"),
                                "status": .string("achieved"),
                            ])
                        }
                    }
                    .disabled(isInactive)
                    Button("Abandon", role: .destructive) {
                        showAbandonConfirm = true
                    }
                    .disabled(isInactive)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Goal actions")
            }
        }
        .sheet(isPresented: $showDescriptionEditor) {
            if let goal {
                DescriptionEditorSheet(store: store, goal: goal)
            }
        }
        .sheet(isPresented: $showAddTactic) {
            TacticEditorSheet(store: store, goalId: goalId)
        }
        .confirmationDialog(
            "Abandon goal?",
            isPresented: $showAbandonConfirm,
            titleVisibility: .visible,
        ) {
            Button("Abandon goal", role: .destructive) {
                Task { await store.patchGoal(id: goalId, ["status": .string("dropped")]) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The goal is grayed out but its history is kept.")
        }
        .confirmationDialog(
            "Delete tactic?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } },
            ),
            presenting: deleteCandidate,
        ) { tactic in
            Button("Delete \(tactic.title)", role: .destructive) {
                Task { await store.deleteTactic(tactic) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Completed weeks are removed with it.")
        }
        .task {
            syncManualState()
            await loadLinks()
        }
        .onChange(of: goal?.manualProgress) {
            syncManualState()
        }
        .onChange(of: model.todayRevision) {
            Task { await loadLinks() }
        }
    }

    private func syncManualState() {
        guard let goal else { return }
        manualEnabled = goal.manualProgress != nil
        if let manual = goal.manualProgress {
            manualValue = Double(manual)
        } else if let progress = goal.progress {
            manualValue = progress * 100
        }
    }

    private func loadLinks() async {
        do {
            async let habitsResponse = model.api.habits()
            async let tasksResponse = model.api.tasks(view: "all", goalId: goalId)
            let (habits, tasks) = try await (habitsResponse, tasksResponse)
            linkedHabits = .loaded(habits.habits.filter { $0.goalId == goalId && $0.archivedAt == nil })
            linkedTasks = .loaded(tasks.tasks.filter { $0.goalId == goalId })
        } catch {
            model.handle(error)
            if linkedHabits.value == nil { linkedHabits = .failed(TodayStore.message(for: error)) }
            if linkedTasks.value == nil { linkedTasks = .failed(TodayStore.message(for: error)) }
        }
    }

    // MARK: - Content

    private func content(_ goal: GoalWithProgressDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if let error = store.mutationError {
                    Text(error)
                        .font(.subheadJ)
                        .foregroundStyle(Color.textSecondary)
                        .padding(Space.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
                header(goal)
                progressCard(goal)
                tacticsSection(goal)
                linkedHabitsSection
                linkedTasksSection
            }
            .padding(PageMargin.standard)
            #if os(macOS)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            #endif
        }
        .opacity(isInactive ? 0.65 : 1)
    }

    // MARK: - Header

    private func header(_ goal: GoalWithProgressDTO) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(goal.title)
                    .font(.title2J)
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: Space.sm)
                if goal.status == "achieved" {
                    TagChip("Achieved")
                } else if goal.status == "dropped" {
                    TagChip("Dropped")
                } else if let trackStatus = goal.trackStatus {
                    TrackStatusPill(status: trackStatus)
                }
            }

            if let areaName = goal.areaName {
                TagChip([goal.areaEmoji, areaName].compactMap { $0 }.joined(separator: " "))
            }

            HStack(alignment: .top, spacing: Space.sm) {
                Text(goal.description?.isEmpty == false ? goal.description! : "No target statement yet")
                    .font(.bodyJ)
                    .foregroundStyle(goal.description?.isEmpty == false ? Color.textSecondary : Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    showDescriptionEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit description")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Progress

    private func progressCard(_ goal: GoalWithProgressDTO) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Progress")
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let progress = goal.progress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.monoJ)
                        .foregroundStyle(Color.textPrimary)
                }
            }

            if let progress = goal.progress {
                PlanProgressBar(fraction: progress)
            } else {
                Text("Add tactics to compute progress")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            }

            Toggle(isOn: manualToggleBinding) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Manual override")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textPrimary)
                    Text(manualEnabled ? "Set the percentage yourself" : "Computed from tactic-weeks")
                        .font(.captionJ)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .toggleStyle(.switch)
            .disabled(isInactive)

            if manualEnabled {
                HStack(spacing: Space.md) {
                    Slider(value: $manualValue, in: 0...100, step: 1) { editing in
                        if !editing { commitManualValue() }
                    }
                    Text("\(Int(manualValue))%")
                        .font(.monoJ)
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private var manualToggleBinding: Binding<Bool> {
        Binding(
            get: { manualEnabled },
            set: { enabled in
                manualEnabled = enabled
                if enabled {
                    commitManualValue()
                } else {
                    Task { await store.patchGoal(id: goalId, ["manualProgress": .null]) }
                }
            },
        )
    }

    private func commitManualValue() {
        let value = Int(manualValue.rounded())
        Task { await store.patchGoal(id: goalId, ["manualProgress": .int(value)]) }
    }

    // MARK: - Tactics

    @ViewBuilder
    private func tacticsSection(_ goal: GoalWithProgressDTO) -> some View {
        SectionHeader("Tactics by Week")
            .padding(.top, Space.xs)

        let tactics = goal.tactics.sorted { $0.sortOrder < $1.sortOrder }
        if tactics.isEmpty {
            Text("No tactics yet — weekly tactics drive this goal's progress")
                .font(.subheadJ)
                .foregroundStyle(Color.textTertiary)
        }

        ForEach(tactics) { tactic in
            tacticRow(tactic)
        }

        Button("+ Add tactic") {
            showAddTactic = true
        }
        .buttonStyle(.jarvisGhost)
        .disabled(isInactive)
    }

    private func tacticRow(_ tactic: TacticDTO) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(tactic.title)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: Space.sm)
                Text(tactic.fromWeek == tactic.toWeek
                    ? "Week \(tactic.fromWeek)"
                    : "Weeks \(tactic.fromWeek)–\(tactic.toWeek)")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }
            TacticWeekCells(
                tactic: tactic,
                completedWeeks: store.completedWeeks(for: tactic),
                currentWeek: currentWeek,
                enabled: !isInactive,
                onToggle: { week, done in
                    Task { await store.setTacticWeek(tactic, weekNumber: week, done: done) }
                },
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard(padding: Space.md)
        .contextMenu {
            Button("Delete", role: .destructive) { deleteCandidate = tactic }
        }
    }

    // MARK: - Linked habits

    @ViewBuilder
    private var linkedHabitsSection: some View {
        SectionHeader("Linked Habits")
            .padding(.top, Space.xs)

        switch linkedHabits {
        case .loaded(let habits):
            if habits.isEmpty {
                Text("No habits linked to this goal")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            } else {
                ForEach(habits) { habit in
                    HStack(spacing: Space.md) {
                        Image(systemName: HabitDisplay.icon(for: habit))
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 24)
                        Text(habit.name)
                            .font(.bodyJ)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: Space.sm)
                        Text(HabitDisplay.typeCaption(for: habit))
                            .font(.captionJ)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .jarvisCard(padding: Space.md)
                }
            }
        case .failed:
            Text("Could not load linked habits")
                .font(.subheadJ)
                .foregroundStyle(Color.textTertiary)
        default:
            ProgressView()
        }
    }

    // MARK: - Linked tasks

    @ViewBuilder
    private var linkedTasksSection: some View {
        SectionHeader("Linked Tasks")
            .padding(.top, Space.xs)

        switch linkedTasks {
        case .loaded(let tasks):
            let open = tasks.filter { $0.status == .open }
            let done = tasks.filter { $0.status == .done }
            if tasks.isEmpty {
                Text("No tasks linked to this goal")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(open) { task in
                        compactTaskRow(task, done: false)
                    }
                    if !done.isEmpty {
                        if !open.isEmpty {
                            Divider()
                        }
                        ForEach(done) { task in
                            compactTaskRow(task, done: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .jarvisCard(padding: Space.md)
            }
        case .failed:
            Text("Could not load linked tasks")
                .font(.subheadJ)
                .foregroundStyle(Color.textTertiary)
        default:
            ProgressView()
        }
    }

    private func compactTaskRow(_ task: TaskDTO, done: Bool) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(done ? Color.success : Color.textTertiary)
            Text(task.title)
                .font(.subheadJ)
                .foregroundStyle(done ? Color.textTertiary : Color.textPrimary)
                .strikethrough(done, color: .textTertiary)
                .lineLimit(1)
            Spacer(minLength: Space.sm)
            if let dueDate = task.dueDate, !done {
                Text(HabitDisplay.shortLabel(for: dueDate))
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}

// MARK: - Week cells

/// A tactic's 12-cell week row: filled when completed, current outlined,
/// out-of-range dimmed, future disabled.
private struct TacticWeekCells: View {
    let tactic: TacticDTO
    let completedWeeks: [Int]
    let currentWeek: Int?
    let enabled: Bool
    let onToggle: (Int, Bool) -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(1...12, id: \.self) { week in
                cell(week)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func cell(_ week: Int) -> some View {
        let inRange = tactic.fromWeek <= week && week <= tactic.toWeek
        let done = completedWeeks.contains(week)
        let isCurrent = week == currentWeek
        let tappable = enabled && inRange && currentWeek.map { week <= $0 } ?? false
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)

        Button {
            onToggle(week, !done)
        } label: {
            shape
                .fill(done ? Color.success.opacity(0.3) : (inRange ? Color.bgSubtle : Color.clear))
                .overlay(
                    shape.strokeBorder(
                        isCurrent ? Color.accentPrimary : (inRange ? Color.borderHairline : Color.borderHairline.opacity(0.4)),
                        lineWidth: isCurrent ? 1.5 : 0.5,
                    ),
                )
                .overlay {
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.success)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 20)
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
        .accessibilityLabel("Week \(week)\(done ? ", completed" : "")")
    }
}

// MARK: - Description editor

private struct DescriptionEditorSheet: View {
    let store: PlanStore
    let goal: GoalWithProgressDTO

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false

    init(store: PlanStore, goal: GoalWithProgressDTO) {
        self.store = store
        self.goal = goal
        _text = State(initialValue: goal.description ?? "")
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.bodyJ)
                .scrollContentBackground(.hidden)
                .padding(PageMargin.standard)
                .background(Color.bgCanvas)
                .navigationTitle("Description")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(isSaving)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }

    private func save() {
        isSaving = true
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await store.patchGoal(
                id: goal.id,
                ["description": trimmed.isEmpty ? .null : .string(trimmed)],
            )
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Tactic editor

/// "+ Add tactic" sheet: title + from/to week steppers.
private struct TacticEditorSheet: View {
    let store: PlanStore
    let goalId: String

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var fromWeek = 1
    @State private var toWeek = 12
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tactic title", text: $title)
                Stepper(value: $fromWeek, in: 1...12) {
                    LabeledContent("From week", value: "\(fromWeek)")
                }
                .onChange(of: fromWeek) {
                    if toWeek < fromWeek { toWeek = fromWeek }
                }
                Stepper(value: $toWeek, in: 1...12) {
                    LabeledContent("To week", value: "\(toWeek)")
                }
                .onChange(of: toWeek) {
                    if fromWeek > toWeek { fromWeek = toWeek }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Tactic")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 260)
        #endif
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        Task {
            await store.createTactic(goalId: goalId, title: trimmed, fromWeek: fromWeek, toWeek: toWeek)
            isSaving = false
            dismiss()
        }
    }
}
