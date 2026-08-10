import DesignSystem
import JarvisAPI
import SwiftUI

/// One goal in full: the two bars, the current reading, and the milestone
/// checklist that carries progress when there is no number to track.
struct GoalDetailView: View {
    let goalId: String
    let store: GoalsStore

    @State private var newMilestone = ""
    @State private var showValueEntry = false
    @State private var valueDraft = ""
    @State private var showEditor = false
    @FocusState private var milestoneFocused: Bool

    private var goal: GoalDTO? { store.goal(goalId) }

    var body: some View {
        Group {
            if let goal {
                content(goal)
            } else {
                // Deleted from another screen while this one was open.
                Text("This goal is gone.")
                    .font(.bodyJ)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle(goal?.title ?? "Goal")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let goal {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit") { showEditor = true }
                        if goal.status == .active {
                            Button("Mark achieved") { store.setStatus(goal, to: .achieved) }
                            Button("Drop") { store.setStatus(goal, to: .dropped) }
                        } else {
                            Button("Reopen") { store.setStatus(goal, to: .active) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let goal {
                GoalEditorView(goal: goal) { draft in
                    store.update(goal, patch: draft.patch) { draft.apply(to: &$0) }
                }
            }
        }
    }

    private func content(_ goal: GoalDTO) -> some View {
        List {
            Group {
                headerCard(goal)
                if let description = goal.description, !description.isEmpty {
                    Text(description)
                        .font(.bodyJ)
                        .foregroundStyle(Color.textSecondary)
                }
                if goal.targetValue != nil {
                    valueCard(goal)
                }
                milestonesSection(goal)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: Space.xs, leading: PageMargin.standard,
                bottom: Space.xs, trailing: PageMargin.standard,
            ))
            #if os(macOS)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            #endif
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func headerCard(_ goal: GoalDTO) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Text(goal.horizon.title)
                    .font(.captionJ)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, 3)
                    .background(Color.bgSubtle, in: Capsule())
                if goal.status != .active {
                    Text(goal.status == .achieved ? "Achieved" : "Dropped")
                        .font(.captionJ)
                        .foregroundStyle(goal.status == .achieved ? Color.success : Color.textTertiary)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 3)
                        .background(
                            goal.status == .achieved ? Color.successSubtle : Color.bgSubtle,
                            in: Capsule(),
                        )
                }
                Spacer(minLength: Space.sm)
                Text("\(DayKeyMath.shortLabel(for: goal.startDate)) → \(DayKeyMath.shortLabel(for: goal.targetDate))")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }
            GoalProgressBars(goal: goal)
            if goal.tracking == .none {
                Text("Add milestones below to give this goal a progress bar.")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Numeric value

    private func valueCard(_ goal: GoalDTO) -> some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Where you are")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
                Text(GoalValueFormat.summary(goal) ?? Placeholder.noValue)
                    .font(.monoJ)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer(minLength: Space.sm)
            Button("Update") {
                valueDraft = GoalValueFormat.string(goal.currentValue ?? goal.startValue ?? 0)
                showValueEntry = true
            }
            .buttonStyle(.jarvisSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
        .alert("Update progress", isPresented: $showValueEntry) {
            TextField("Value", text: $valueDraft)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let value = Double(valueDraft.replacingOccurrences(of: ",", with: ".")) {
                    store.setValue(goal, to: value)
                }
            }
        } message: {
            Text(goal.unit.map { "Current value in \($0)." } ?? "Current value.")
        }
    }

    // MARK: - Milestones

    @ViewBuilder
    private func milestonesSection(_ goal: GoalDTO) -> some View {
        SectionHeader("Milestones")
            .padding(.top, Space.md)

        ForEach(goal.milestones.sorted { $0.sortOrder < $1.sortOrder }) { milestone in
            HStack(spacing: Space.md) {
                Button {
                    store.setMilestone(milestone, in: goal, done: !milestone.isDone)
                } label: {
                    Image(systemName: milestone.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(milestone.isDone ? Color.success : Color.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                Text(milestone.title)
                    .font(.bodyJ)
                    .foregroundStyle(milestone.isDone ? Color.textTertiary : Color.textPrimary)
                    .strikethrough(milestone.isDone, color: .textTertiary)

                Spacer(minLength: Space.sm)
            }
            .frame(minHeight: RowHeight.standard)
            .contentShape(Rectangle())
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) {
                    store.deleteMilestone(milestone, in: goal)
                }
            }
            .contextMenu {
                Button("Delete", role: .destructive) {
                    store.deleteMilestone(milestone, in: goal)
                }
            }
        }

        HStack(spacing: Space.md) {
            Image(systemName: "plus.circle")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.textTertiary)
            TextField("Add a milestone", text: $newMilestone)
                .font(.bodyJ)
                .textFieldStyle(.plain)
                .focused($milestoneFocused)
                .onSubmit {
                    store.addMilestone(to: goal, title: newMilestone)
                    newMilestone = ""
                    milestoneFocused = true
                }
        }
        .frame(minHeight: RowHeight.standard)
    }
}
