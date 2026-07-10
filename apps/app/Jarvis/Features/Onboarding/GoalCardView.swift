import DesignSystem
import JarvisAPI
import SwiftUI

/// One editable goal card on the Plan Proposal Review: inline title, area
/// chip, target line, collapsible tactics and habits & tasks groups.
struct GoalCardView: View {
    @Binding var goal: PlanGoalDTO
    let areas: [PlanAreaDTO]
    let onRemove: () -> Void

    @State private var activeSheet: GoalSheet?
    @State private var confirmingRemove = false
    @State private var tacticsExpanded = true
    @State private var itemsExpanded = true

    enum GoalSheet: Identifiable, Hashable {
        case addTactic
        case editTactic(Int)
        case addHabit
        case editHabit(Int)
        case addTask
        case editTask(Int)

        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header
            areaAndTarget
            tacticsGroup
            itemsGroup
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
        .confirmationDialog(
            "Remove this goal?",
            isPresented: $confirmingRemove,
            titleVisibility: .visible,
        ) {
            Button("Remove goal", role: .destructive) { onRemove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its tactics, habits, and tasks won't be created.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            TextField("Goal title", text: $goal.title, axis: .vertical)
                .font(.headlineJ)
                .foregroundStyle(Color.textPrimary)
                .textFieldStyle(.plain)
            Menu {
                Button("Remove goal", role: .destructive) {
                    confirmingRemove = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Goal options")
        }
    }

    private var areaAndTarget: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            areaMenu
            if !goal.targetLine.isEmpty {
                Text(goal.targetLine)
                    .font(.captionJ)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var areaMenu: some View {
        Menu {
            Button("None") { goal.areaIndex = nil }
            ForEach(areas.indices, id: \.self) { index in
                Button(areaLabel(areas[index])) { goal.areaIndex = index }
            }
        } label: {
            HStack(spacing: Space.xs) {
                Text(currentAreaLabel)
                    .font(.captionJ)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Color.accentPrimary)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 3)
            .background(Color.accentSubtle, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Area: \(currentAreaLabel)")
    }

    private var currentAreaLabel: String {
        if let index = goal.areaIndex, areas.indices.contains(index) {
            return areaLabel(areas[index])
        }
        return "No area"
    }

    private func areaLabel(_ area: PlanAreaDTO) -> String {
        if let emoji = area.emoji, !emoji.isEmpty { return "\(emoji) \(area.name)" }
        return area.name
    }

    // MARK: - Weekly tactics

    private var tacticsGroup: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            groupHeader("Weekly tactics", expanded: $tacticsExpanded)
            if tacticsExpanded {
                ForEach(goal.tactics.indices, id: \.self) { index in
                    tacticRow(index)
                }
                addRow("+ Add tactic") { activeSheet = .addTactic }
            }
        }
    }

    private func tacticRow(_ index: Int) -> some View {
        let tactic = goal.tactics[index]
        return HStack(spacing: Space.sm) {
            Text(tactic.title)
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.sm)
            Text("wks \(tactic.fromWeek)–\(tactic.toWeek)")
                .font(.monoJ)
                .foregroundStyle(Color.textSecondary)
            rowButton("pencil", label: "Edit tactic") { activeSheet = .editTactic(index) }
            rowButton("xmark", label: "Remove tactic") {
                withAnimation(.easeOut(duration: 0.2)) {
                    guard goal.tactics.indices.contains(index) else { return }
                    goal.tactics.remove(at: index)
                }
            }
        }
        .padding(.vertical, Space.xs)
    }

    // MARK: - Habits & tasks

    private var itemsGroup: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            groupHeader("Habits & tasks", expanded: $itemsExpanded)
            if itemsExpanded {
                ForEach(goal.habits.indices, id: \.self) { index in
                    habitRow(index)
                }
                ForEach(goal.tasks.indices, id: \.self) { index in
                    taskRow(index)
                }
                HStack(spacing: Space.lg) {
                    addRow("+ Add habit") { activeSheet = .addHabit }
                    addRow("+ Add task") { activeSheet = .addTask }
                }
            }
        }
    }

    private func habitRow(_ index: Int) -> some View {
        let habit = goal.habits[index]
        return HStack(spacing: Space.sm) {
            typeBadge("HABIT")
            VStack(alignment: .leading, spacing: 1) {
                Text(habit.name)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textPrimary)
                Text(PlanDraftDisplay.summary(for: habit))
                    .font(.captionJ)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Space.sm)
            rowButton("pencil", label: "Edit habit") { activeSheet = .editHabit(index) }
            rowButton("xmark", label: "Remove habit") {
                withAnimation(.easeOut(duration: 0.2)) {
                    guard goal.habits.indices.contains(index) else { return }
                    goal.habits.remove(at: index)
                }
            }
        }
        .padding(.vertical, Space.xs)
    }

    private func taskRow(_ index: Int) -> some View {
        let task = goal.tasks[index]
        return HStack(spacing: Space.sm) {
            typeBadge("TASK")
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textPrimary)
                Text(PlanDraftDisplay.summary(for: task))
                    .font(.captionJ)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Space.sm)
            rowButton("pencil", label: "Edit task") { activeSheet = .editTask(index) }
            rowButton("xmark", label: "Remove task") {
                withAnimation(.easeOut(duration: 0.2)) {
                    guard goal.tasks.indices.contains(index) else { return }
                    goal.tasks.remove(at: index)
                }
            }
        }
        .padding(.vertical, Space.xs)
    }

    // MARK: - Shared bits

    private func groupHeader(_ title: String, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: Space.xs) {
                Text(title.uppercased())
                    .font(.captionJ)
                    .tracking(0.6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(.degrees(expanded.wrappedValue ? 0 : -90))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, Space.xs)
    }

    private func typeBadge(_ text: String) -> some View {
        Text(text)
            .font(.captionJ)
            .tracking(0.6)
            .foregroundStyle(Color.accentPrimary)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 2)
            .background(Color.accentSubtle, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
    }

    private func rowButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.subheadJ)
            .foregroundStyle(Color.accentPrimary)
            .padding(.vertical, Space.xs)
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: GoalSheet) -> some View {
        switch sheet {
        case .addTactic:
            TacticEditSheet(title: "", fromWeek: 1, toWeek: 12) { title, from, to in
                goal.tactics.append(PlanTacticDTO(title: title, fromWeek: from, toWeek: to))
            }
        case .editTactic(let index):
            if goal.tactics.indices.contains(index) {
                let tactic = goal.tactics[index]
                TacticEditSheet(title: tactic.title, fromWeek: tactic.fromWeek, toWeek: tactic.toWeek) { title, from, to in
                    guard goal.tactics.indices.contains(index) else { return }
                    goal.tactics[index].title = title
                    goal.tactics[index].fromWeek = from
                    goal.tactics[index].toWeek = to
                }
            }
        case .addHabit:
            HabitEditSheet(name: "", type: .daily, targetReps: 1, plannedDays: []) { name, type, reps, days in
                goal.habits.append(PlanHabitDTO(name: name, type: type, targetReps: reps, plannedDays: days))
            }
        case .editHabit(let index):
            if goal.habits.indices.contains(index) {
                let habit = goal.habits[index]
                HabitEditSheet(
                    name: habit.name,
                    type: habit.type,
                    targetReps: habit.targetReps,
                    plannedDays: Set(habit.plannedDays),
                ) { name, type, reps, days in
                    guard goal.habits.indices.contains(index) else { return }
                    goal.habits[index].name = name
                    goal.habits[index].type = type
                    goal.habits[index].targetReps = reps
                    goal.habits[index].plannedDays = days
                }
            }
        case .addTask:
            TaskEditSheet(title: "", priority: .medium, dueOffsetDays: nil) { title, priority, dueOffset in
                goal.tasks.append(PlanTaskDTO(title: title, dueOffsetDays: dueOffset, priority: priority))
            }
        case .editTask(let index):
            if goal.tasks.indices.contains(index) {
                let task = goal.tasks[index]
                TaskEditSheet(title: task.title, priority: task.priority, dueOffsetDays: task.dueOffsetDays) { title, priority, dueOffset in
                    guard goal.tasks.indices.contains(index) else { return }
                    goal.tasks[index].title = title
                    goal.tasks[index].priority = priority
                    goal.tasks[index].dueOffsetDays = dueOffset
                }
            }
        }
    }
}
