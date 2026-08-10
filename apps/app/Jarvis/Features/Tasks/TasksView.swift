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
                categoryChips
                // Always there, above the tasks — adding one is typing, not
                // opening something first.
                quickAdd
                if let actionError = store.actionError {
                    inlineError(actionError)
                }
                listBody
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
        .refreshable { await store.fetch(force: true) }
        .background(Color.bgCanvas)
        .navigationTitle("Tasks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            segmentPicker
                .padding(.horizontal, PageMargin.standard)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.sm)
                .background(Color.bgCanvas)
        }
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .principal) { segmentPicker }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    composerActive = true
                } label: {
                    Label("New task", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
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
            Text("Tasks in this category are kept. They just lose the category.")
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

    private var quickAdd: some View {
        QuickAddComposer(
            todayKey: store.todayKey,
            categories: store.categories,
            defaults: composerDefaults,
            isActive: $composerActive,
            onCreate: { store.create($0) },
            onCreateCategory: { await store.createCategory(name: $0) },
            onOpenEditor: { editorDraft = $0 },
        )
    }

    #if os(macOS)
    private var inspectorShown: Binding<Bool> {
        Binding(
            get: { selectedTaskId != nil },
            set: { if !$0 { selectedTaskId = nil } },
        )
    }
    #endif

    // MARK: - Segment picker
    //
    // Lives in the toolbar on macOS and a top safe-area inset on iOS, matching
    // Progress exactly. It also keeps working in every load state, which a
    // first-scrolling-row picker does not.

    private var segmentPicker: some View {
        ChipPicker(
            TasksStore.Segment.allCases,
            selection: $store.segment,
            fillsWidth: fillsWidth,
        ) { $0.title }
    }

    private var fillsWidth: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, Space.md)
                        .padding(.vertical, 7)
                        .background(Color.bgSubtle, in: Capsule())
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
        // A selected category wears its own colour rather than the app accent:
        // the chip row is the one place the categories are being compared, so
        // that is exactly where their colours should be doing the work.
        let tint = dotColor ?? .accentPrimary
        return Button {
            Haptics.play(.light)
            withJarvisAnimation(Motion.quick) { action() }
        } label: {
            HStack(spacing: 5) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.captionJ)
            }
            .foregroundStyle(isSelected ? tint : Color.textSecondary)
            .padding(.horizontal, Space.md)
            .padding(.vertical, 7)
            .background(isSelected ? tint.opacity(0.14) : Color.bgSubtle, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
                emptyState("No tasks today")
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
                emptyState("No tasks yet")
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

    private func captionHeader(_ title: String, color: Color = .textTertiary) -> some View {
        CaptionLabel(title, color: color)
            .padding(.top, Space.sm)
    }

    private func emptyState(_ message: String) -> some View {
        EmptyState(
            symbol: emptySymbol,
            title: message,
            message: emptyDetail,
            tint: ItemColor.blue.color,
        ) {
            if store.segment != .done {
                Button("Add a task") { composerActive = true }
                    .buttonStyle(.jarvisPrimary)
            }
        }
    }

    private var emptySymbol: String {
        switch store.segment {
        case .today: "checkmark.circle"
        case .upcoming: "calendar"
        case .all: "tray"
        case .done: "archivebox"
        }
    }

    private var emptyDetail: String? {
        switch store.segment {
        case .today: "Nothing due today. Add one above, or enjoy it."
        case .upcoming: "Nothing scheduled after today."
        case .all: nil
        case .done: "Completed tasks collect here."
        }
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.danger)
            Text(message)
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: Space.sm)
            Button("Dismiss") { store.actionError = nil }
                .buttonStyle(.jarvisSoft)
        }
        .padding(Space.md)
        .background(Color.dangerSubtle, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }
}
