import DesignSystem
import JarvisAPI
import SwiftUI

/// Route wrapper so a task id can drive `navigationDestination(item:)`.
private struct TaskRoute: Identifiable, Hashable {
    let id: String
}

/// Tasks tab. Structured like TodayView: ONE List owns the whole page —
/// the segment chips are the first scrolling row, never a fixed bar. On
/// macOS a fixed region under the title makes the window toolbar paint its
/// permanent opaque band; a scroll view at the top edge keeps it transparent.
struct TasksView: View {
    @Environment(AppModel.self) private var model
    @State private var store = TasksStore()
    @State private var showingEditor = false
    @State private var showingRecurring = false
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    #if os(macOS)
    @State private var selectedTaskId: String?
    #else
    @State private var detailRoute: TaskRoute?
    #endif

    var body: some View {
        List {
            Group {
                controlsRow
                if showSearch {
                    searchField
                }
                if let actionError = store.actionError {
                    inlineError(actionError)
                }
                listBody
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
        .refreshable { await store.fetch(force: true) }
        .background(Color.bgCanvas)
        .navigationTitle("Tasks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Label("New task", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("Recurring tasks") { showingRecurring = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            TaskEditorView(goals: store.goals, defaultDueDate: store.todayKey) {
                await store.fetch()
            }
        }
        .navigationDestination(isPresented: $showingRecurring) {
            RecurringTasksView()
        }
        #if os(macOS)
        .inspector(isPresented: inspectorShown) {
            if let selectedTaskId {
                NavigationStack {
                    TaskDetailView(taskId: selectedTaskId, store: store) {
                        self.selectedTaskId = nil
                    }
                }
                .inspectorColumnWidth(min: 300, ideal: 320, max: 400)
            }
        }
        #else
        .navigationDestination(item: $detailRoute) { route in
            TaskDetailView(taskId: route.id, store: store)
        }
        #endif
        .task {
            store.bind(model)
            await store.fetchGoals()
            await store.fetch()
        }
    }

    #if os(macOS)
    private var inspectorShown: Binding<Bool> {
        Binding(
            get: { selectedTaskId != nil },
            set: { if !$0 { selectedTaskId = nil } },
        )
    }
    #endif

    // MARK: - Controls (first list row)

    private var controlsRow: some View {
        HStack(spacing: Space.sm) {
            ChipPicker(TasksStore.Segment.allCases, selection: $store.segment) { $0.title }
            searchToggle
        }
        .padding(.top, Space.xs)
    }

    // MARK: - Search (inline — the system .searchable forces heavy
    // window-toolbar chrome on macOS, so search lives in the content instead)

    private var searchToggle: some View {
        Button {
            if showSearch {
                store.searchText = ""
                showSearch = false
            } else {
                showSearch = true
                searchFocused = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(showSearch ? Color.accentPrimary : Color.textSecondary)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, 6)
                .background(showSearch ? Color.accentSubtle : Color.bgSubtle, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityLabel(showSearch ? "Close search" : "Search tasks")
    }

    private var searchField: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiary)
            TextField("Search tasks", text: Bindable(store).searchText)
                .font(.subheadJ)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 6)
        .background(Color.bgSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 0.5))
    }

    // MARK: - List body

    @ViewBuilder
    private var listBody: some View {
        switch store.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xxl * 2)
        case .failed(let message):
            VStack(spacing: Space.md) {
                Text(message)
                    .font(.subheadJ)
                    .foregroundStyle(Color.danger)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await store.fetch() }
                }
                .buttonStyle(.jarvisSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xxl)
        case .loaded:
            segmentBody
        }
    }

    @ViewBuilder
    private var segmentBody: some View {
        switch store.segment {
        case .today:
            let overdue = store.overdueTasks
            let today = store.todayTasks
            if overdue.isEmpty && today.isEmpty {
                emptyState("No tasks today — add one")
            } else {
                if !overdue.isEmpty {
                    Section {
                        ForEach(overdue) { task in
                            row(
                                for: task,
                                overdueLabel: task.dueDate.map { "was due \(TaskDateLabels.shortLabel(for: $0))" },
                            )
                        }
                    } header: {
                        captionHeader("Overdue", color: .warning)
                    }
                }
                if !today.isEmpty {
                    Section {
                        ForEach(today) { task in
                            row(for: task)
                        }
                    } header: {
                        captionHeader("Today")
                    }
                }
            }
        case .upcoming:
            let groups = store.upcomingGroups
            if groups.isEmpty {
                emptyState("Nothing scheduled ahead")
            } else {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.tasks) { task in
                            row(for: task)
                        }
                    } header: {
                        captionHeader(group.title)
                    }
                }
            }
        case .all:
            let tasks = store.allTasks
            if tasks.isEmpty {
                emptyState("No tasks — add one")
            } else {
                ForEach(tasks) { task in
                    row(for: task)
                }
            }
        case .done:
            let tasks = store.doneTasks
            if tasks.isEmpty {
                emptyState("Nothing completed yet")
            } else {
                ForEach(tasks) { task in
                    VStack(alignment: .leading, spacing: 0) {
                        row(for: task)
                        if let completedAt = task.completedAt,
                           let label = TaskDateLabels.completedLabel(for: completedAt) {
                            Text("Completed \(label)")
                                .font(.captionJ)
                                .foregroundStyle(Color.textTertiary)
                                .padding(.leading, 34)
                                .padding(.bottom, Space.xs)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rows & helpers

    private func row(for task: TaskDTO, overdueLabel: String? = nil) -> some View {
        TaskRow(
            task: task,
            goalTitle: store.goalTitle(for: task.goalId),
            overdueLabel: overdueLabel,
            onToggle: {
                Task { await store.toggleComplete(task) }
            },
            onTap: { open(task) },
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if task.status == .open {
                Button {
                    Task { await store.toggleComplete(task) }
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .tint(.success)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if task.status == .open {
                Button {
                    Task { await store.reschedule(task, to: store.todayKey) }
                } label: {
                    Label("Today", systemImage: "sun.max")
                }
                .tint(.accentPrimary)

                Button {
                    Task { await store.reschedule(task, to: DayKeyMath.addDays(store.todayKey, 1)) }
                } label: {
                    Label("Tomorrow", systemImage: "arrow.right")
                }
                .tint(.textSecondary)
            }
        }
    }

    private func open(_ task: TaskDTO) {
        #if os(macOS)
        selectedTaskId = task.id
        #else
        detailRoute = TaskRoute(id: task.id)
        #endif
    }

    private func captionHeader(_ title: String, color: Color = .textSecondary) -> some View {
        Text(title.uppercased())
            .font(.captionJ)
            .tracking(0.6)
            .foregroundStyle(color)
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: Space.md) {
            Text(message)
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
            Button("Add task") { showingEditor = true }
                .buttonStyle(.jarvisGhost)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl * 2)
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: Space.sm) {
            Text(message)
                .font(.subheadJ)
                .foregroundStyle(Color.danger)
            Spacer(minLength: Space.sm)
            Button("Dismiss") { store.actionError = nil }
                .font(.subheadJ)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentPrimary)
        }
    }
}
