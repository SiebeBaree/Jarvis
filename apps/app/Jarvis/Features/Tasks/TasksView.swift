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
    /// Quick-add composer state: collapsed pill ⇄ open composer.
    @State private var composerActive = false
    /// Non-nil while the full editor is up, carrying what quick-add had typed.
    @State private var editorDraft: TaskDraft?
    @State private var showNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var renameCategoryTarget: TaskCategoryDTO?
    @State private var renameCategoryName = ""
    @State private var deleteCategoryTarget: TaskCategoryDTO?
    #if os(macOS)
    @State private var selectedTaskId: String?
    #else
    @State private var detailRoute: TaskRoute?
    #endif

    var body: some View {
        List {
            Group {
                controlsRow
                categoryChips
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
                    composerActive = true
                } label: {
                    Label("New task", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        // The composer lives at the bottom edge, always one tap (or ⌘N) away
        // and never scrolled off — and it keeps the List owning the top edge,
        // which is what keeps the macOS toolbar band transparent.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            quickAddBar
        }
        .sheet(item: $editorDraft) { draft in
            TaskEditorView(draft: draft) { request in
                store.create(request)
            }
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
            await store.fetchCategories()
            await store.fetch()
        }
        // Mutations anywhere (here, Today, the detail sheet) invalidate the
        // cache and bump this; the list then revalidates in the background.
        .onChange(of: model.dataRevision) {
            Task { await store.fetch() }
        }
        .alert("New category", isPresented: $showNewCategoryAlert) {
            TextField("Name", text: $newCategoryName)
            Button("Create") {
                let name = newCategoryName
                newCategoryName = ""
                Task {
                    if let created = await store.createCategory(name: name) {
                        store.selectedCategoryId = created.id
                    }
                }
            }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        } message: {
            Text("e.g. Work, Personal, Household")
        }
        .alert(
            "Rename category",
            isPresented: Binding(
                get: { renameCategoryTarget != nil },
                set: { if !$0 { renameCategoryTarget = nil } },
            ),
            presenting: renameCategoryTarget,
        ) { category in
            TextField("Name", text: $renameCategoryName)
            Button("Rename") {
                let name = renameCategoryName
                Task { await store.renameCategory(category, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            EmptyView()
        }
        .confirmationDialog(
            "Delete category?",
            isPresented: Binding(
                get: { deleteCategoryTarget != nil },
                set: { if !$0 { deleteCategoryTarget = nil } },
            ),
            presenting: deleteCategoryTarget,
        ) { category in
            Button("Delete \(category.name)", role: .destructive) {
                Task { await store.deleteCategory(category) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Tasks in this category are kept — they just lose the category.")
        }
    }

    // MARK: - Quick add

    /// A new task inherits the page you are looking at: Upcoming means
    /// tomorrow, and a category filter means that category.
    private var composerDefaults: TaskDraft {
        var draft = TaskDraft()
        draft.dueDate = switch store.segment {
        case .today, .all, .done: store.todayKey
        case .upcoming: DayKeyMath.addDays(store.todayKey, 1)
        }
        draft.categoryId = store.selectedCategoryId
        return draft
    }

    private var quickAddBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderHairline)
                .frame(height: 0.5)
            QuickAddComposer(
                todayKey: store.todayKey,
                categories: store.categories,
                defaults: composerDefaults,
                isActive: $composerActive,
                onCreate: { store.create($0) },
                onCreateCategory: { await store.createCategory(name: $0) },
                onOpenEditor: { editorDraft = $0 },
            )
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.xs)
            #if os(macOS)
            .frame(maxWidth: 760)
            #endif
            .frame(maxWidth: .infinity)
        }
        .background(Color.bgSurface)
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
        ChipPicker(TasksStore.Segment.allCases, selection: $store.segment) { $0.title }
            .padding(.top, Space.xs)
    }

    // MARK: - Category pages (TickTick-style filter chips)

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                categoryChip(title: "All", isSelected: store.selectedCategoryId == nil, dotColor: nil) {
                    store.selectedCategoryId = nil
                }
                ForEach(store.categories) { category in
                    categoryChip(
                        title: category.name,
                        isSelected: store.selectedCategoryId == category.id,
                        dotColor: Color(hexString: category.colorHex) ?? .textTertiary,
                    ) {
                        store.selectedCategoryId = store.selectedCategoryId == category.id ? nil : category.id
                    }
                    .contextMenu {
                        Button("Rename") {
                            renameCategoryName = category.name
                            renameCategoryTarget = category
                        }
                        Button("Delete", role: .destructive) {
                            deleteCategoryTarget = category
                        }
                    }
                }
                Button {
                    newCategoryName = ""
                    showNewCategoryAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 6)
                        .background(Color.bgSubtle, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New category")
            }
        }
    }

    private func categoryChip(
        title: String,
        isSelected: Bool,
        dotColor: Color?,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.captionJ)
            }
            .foregroundStyle(isSelected ? Color.accentPrimary : Color.textSecondary)
            .padding(.horizontal, Space.md)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentSubtle : Color.bgSubtle, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
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
            // Hide the chip while filtering on that category — pure noise then.
            category: store.selectedCategoryId == nil ? store.category(for: task.categoryId) : nil,
            overdueLabel: overdueLabel,
            onToggle: {
                store.toggleComplete(task)
            },
            onTap: { open(task) },
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if task.status == .open {
                Button {
                    store.toggleComplete(task)
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .tint(.success)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if task.status == .open {
                Button {
                    store.reschedule(task, to: store.todayKey)
                } label: {
                    Label("Today", systemImage: "sun.max")
                }
                .tint(.accentPrimary)

                Button {
                    store.reschedule(task, to: DayKeyMath.addDays(store.todayKey, 1))
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
            Button("Add task") { composerActive = true }
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
