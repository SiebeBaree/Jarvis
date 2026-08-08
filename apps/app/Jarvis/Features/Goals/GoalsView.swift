import DesignSystem
import JarvisAPI
import SwiftUI

/// The Goals tab: what you're actually aiming at, short term and long term,
/// each showing how much of the clock has run against how much of the goal is
/// done.
struct GoalsView: View {
    @Environment(AppModel.self) private var model

    @State private var store = GoalsStore()
    @State private var editing: GoalEditorRoute?
    @State private var selected: GoalRoute?
    @State private var showClosed = false

    var body: some View {
        Group {
            if store.content.value != nil {
                list
            } else if case .failed(let message) = store.content {
                errorState(message)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = GoalEditorRoute(goal: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New goal")
            }
        }
        .sheet(item: $editing) { route in
            GoalEditorView(goal: route.goal) { request in
                if let existing = route.goal {
                    store.update(existing, patch: request.patch) { request.apply(to: &$0) }
                } else {
                    store.create(request.create)
                }
            }
        }
        .navigationDestination(item: $selected) { route in
            GoalDetailView(goalId: route.id, store: store)
        }
        .task {
            store.configure(model)
            await store.load()
        }
        .onChange(of: model.dataRevision) {
            Task { await store.load() }
        }
    }

    private var list: some View {
        List {
            Group {
                if let error = store.mutationError {
                    Text(error)
                        .font(.subheadJ)
                        .foregroundStyle(Color.textSecondary)
                }

                if store.goals.isEmpty {
                    emptyState
                }

                horizonSection(.short)
                horizonSection(.long)
                closedSection
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

    @ViewBuilder
    private func horizonSection(_ horizon: GoalHorizon) -> some View {
        let goals = store.active(horizon)
        if !goals.isEmpty {
            SectionHeader(horizon.title)
                .padding(.top, Space.sm)
        }
        ForEach(goals) { goal in
            GoalCard(goal: goal)
                .contentShape(Rectangle())
                .onTapGesture { selected = GoalRoute(id: goal.id) }
                .contextMenu {
                    Button("Edit") { editing = GoalEditorRoute(goal: goal) }
                    Button("Mark achieved") { store.setStatus(goal, to: .achieved) }
                    Button("Drop") { store.setStatus(goal, to: .dropped) }
                    Divider()
                    Button("Delete", role: .destructive) { store.delete(goal) }
                }
        }
    }

    @ViewBuilder
    private var closedSection: some View {
        let closed = store.closed
        if !closed.isEmpty {
            Button {
                withAnimation(.easeOut(duration: 0.25)) { showClosed.toggle() }
            } label: {
                HStack(spacing: Space.xs) {
                    Text("Closed (\(closed.count))")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: showClosed ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, Space.md)
        }

        ForEach(showClosed ? closed : []) { goal in
            GoalCard(goal: goal)
                .opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { selected = GoalRoute(id: goal.id) }
                .contextMenu {
                    Button("Reopen") { store.setStatus(goal, to: .active) }
                    Button("Delete", role: .destructive) { store.delete(goal) }
                }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.sm) {
            Text("No goals yet")
                .font(.headlineJ)
                .foregroundStyle(Color.textPrimary)
            Text("Write down what you're aiming at and by when. Jarvis tracks the clock against your progress.")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Add a goal") { editing = GoalEditorRoute(goal: nil) }
                .buttonStyle(.jarvisPrimary)
                .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Space.lg) {
            Text(message)
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await store.load(force: true) } }
                .buttonStyle(.jarvisSecondary)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Navigation route to a goal's detail screen.
struct GoalRoute: Identifiable, Hashable {
    let id: String
}

/// Sheet route — `nil` goal means "new".
struct GoalEditorRoute: Identifiable {
    let goal: GoalDTO?
    var id: String { goal?.id ?? "new" }
}

// MARK: - Card

struct GoalCard: View {
    let goal: GoalDTO

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(goal.title)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: Space.sm)
                trailingSummary
            }
            GoalProgressBars(goal: goal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    @ViewBuilder
    private var trailingSummary: some View {
        switch goal.tracking {
        case .numeric:
            if let summary = GoalValueFormat.summary(goal) {
                Text(summary)
                    .font(.monoJ)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        case .milestones:
            Text("\(goal.milestonesDone)/\(goal.milestonesTotal)")
                .font(.monoJ)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
        case .none:
            Text(DayKeyMath.shortLabel(for: goal.targetDate))
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
        }
    }
}
