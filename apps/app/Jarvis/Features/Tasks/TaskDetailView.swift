import DesignSystem
import JarvisAPI
import SwiftUI

/// Task detail: inline-editable title, property rows, subtasks checklist,
/// notes, and delete. iOS pushes onto the Tasks stack; macOS shows it in the
/// trailing inspector.
struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let taskId: String
    let store: TasksStore
    var onClose: (() -> Void)? = nil

    @State private var task: TaskDTO?
    @State private var loadFailed = false
    @State private var errorMessage: String?

    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var newSubtaskTitle = ""
    @State private var showingDeleteConfirm = false
    @State private var showingRecurring = false

    @FocusState private var notesFocused: Bool

    var body: some View {
        Group {
            if let task {
                detailList(for: task)
            } else if loadFailed {
                VStack(spacing: Space.md) {
                    Text("Could not load this task.")
                        .font(.subheadJ)
                        .foregroundStyle(Color.danger)
                    Button("Retry") {
                        Task { await load() }
                    }
                    .buttonStyle(.jarvisSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle("Task")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(isPresented: $showingRecurring) {
            RecurringTasksView()
        }
        .task(id: taskId) {
            await load()
        }
        .onDisappear {
            saveNotesIfChanged()
        }
    }

    private func load() async {
        loadFailed = false
        if let cached = store.task(withId: taskId) {
            apply(cached)
        }
        if let fresh = await store.refreshTask(id: taskId) {
            apply(fresh)
        } else if task == nil {
            loadFailed = true
        }
    }

    private func apply(_ task: TaskDTO) {
        self.task = task
        titleDraft = task.title
        notesDraft = task.notes ?? ""
    }

    // MARK: - Layout

    private func detailList(for task: TaskDTO) -> some View {
        List {
            Section {
                TextField("Title", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.title2J)
                    .foregroundStyle(Color.textPrimary)
                    .onSubmit { saveTitle() }
                    .listRowBackground(Color.bgCanvas)
                    .listRowSeparator(.hidden)

                statusRow(for: task)
                    .listRowBackground(Color.bgCanvas)
                    .listRowSeparator(.hidden)
            }

            Section {
                dueDateRow(for: task)
                timeRow(for: task)
                priorityRow(for: task)
                categoryRow(for: task)
                goalRow(for: task)
                if task.templateId != nil {
                    repeatsRow
                }
            } header: {
                sectionCaption("Details")
            }
            .listRowBackground(Color.bgSurface)

            Section {
                if !task.subtasks.isEmpty {
                    subtaskProgress(for: task)
                        .listRowBackground(Color.bgSurface)
                }
                ForEach(task.subtasks.filter { $0.status != .cancelled }) { subtask in
                    subtaskRow(subtask)
                        .listRowBackground(Color.bgSurface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteSubtask(subtask)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                addSubtaskRow(for: task)
                    .listRowBackground(Color.bgSurface)
            } header: {
                sectionCaption("Subtasks")
            }

            Section {
                TextEditor(text: $notesDraft)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 88)
                    .focused($notesFocused)
                    .onChange(of: notesFocused) { _, focused in
                        if !focused { saveNotesIfChanged() }
                    }
                    .listRowBackground(Color.bgSurface)
            } header: {
                sectionCaption("Notes")
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Text("Delete task")
                        .font(.headlineJ)
                        .foregroundStyle(Color.danger)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.bgCanvas)
                .listRowSeparator(.hidden)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.subheadJ)
                        .foregroundStyle(Color.danger)
                        .listRowBackground(Color.bgCanvas)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .confirmationDialog(
            task.templateId != nil ? "Delete recurring task" : "Delete task",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible,
        ) {
            if let templateId = task.templateId {
                Button("This occurrence", role: .destructive) {
                    deleteTask()
                }
                Button("All future occurrences", role: .destructive) {
                    deleteTemplate(templateId)
                }
            } else {
                Button("Delete", role: .destructive) {
                    deleteTask()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                task.templateId != nil
                    ? "This task repeats. Choose what to delete."
                    : "This cannot be undone.",
            )
        }
    }

    private func sectionCaption(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.captionJ)
            .tracking(0.6)
            .foregroundStyle(Color.textSecondary)
    }

    // MARK: - Status

    private func statusRow(for task: TaskDTO) -> some View {
        HStack(spacing: Space.md) {
            Button {
                toggleComplete()
            } label: {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(task.status == .done ? Color.success : Color.textTertiary)
            }
            .buttonStyle(.plain)

            if task.status == .done, let completedAt = task.completedAt,
               let label = TaskDateLabels.completedLabel(for: completedAt) {
                Text("Completed \(label)")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("Open")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - Property rows

    private func propertyLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadJ)
            .foregroundStyle(Color.textSecondary)
            .frame(width: 72, alignment: .leading)
    }

    private func dueDateRow(for task: TaskDTO) -> some View {
        HStack(spacing: Space.md) {
            propertyLabel("Due date")
            Spacer(minLength: 0)
            if let dueDate = task.dueDate {
                DatePicker(
                    "Due date",
                    selection: Binding(
                        get: { DayKeyMath.date(from: dueDate) ?? .now },
                        set: { newDate in
                            patch(["dueDate": .string(Self.dayKey(from: newDate))]) { $0.with(dueDate: Self.dayKey(from: newDate)) }
                        },
                    ),
                    displayedComponents: .date,
                )
                .labelsHidden()
                Button {
                    patch(["dueDate": .null]) { $0.with(dueDate: .some(nil)) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear due date")
            } else {
                Button("None — set date") {
                    patch(["dueDate": .string(store.todayKey)]) { $0.with(dueDate: store.todayKey) }
                }
                .buttonStyle(.jarvisGhost)
            }
        }
        .frame(minHeight: RowHeight.standard)
    }

    private func timeRow(for task: TaskDTO) -> some View {
        HStack(spacing: Space.md) {
            propertyLabel("Time")
            Spacer(minLength: 0)
            if let dueTime = task.dueTime {
                DatePicker(
                    "Time",
                    selection: Binding(
                        get: { Self.timeDate(from: dueTime) },
                        set: { newDate in
                            patch(["dueTime": .string(Self.timeString(from: newDate))]) { $0.with(dueTime: Self.timeString(from: newDate)) }
                        },
                    ),
                    displayedComponents: .hourAndMinute,
                )
                .labelsHidden()
                Button {
                    patch(["dueTime": .null]) { $0.with(dueTime: .some(nil)) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear time")
            } else {
                Button("None — set time") {
                    patch(["dueTime": .string("09:00")]) { $0.with(dueTime: "09:00") }
                }
                .buttonStyle(.jarvisGhost)
            }
        }
        .frame(minHeight: RowHeight.standard)
    }

    private func priorityRow(for task: TaskDTO) -> some View {
        HStack(spacing: Space.md) {
            propertyLabel("Priority")
            Spacer(minLength: 0)
            Menu {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    Button {
                        patch(["priority": .string(priority.rawValue)]) { $0.with(priority: priority) }
                    } label: {
                        Label(
                            priority.flagLevel.label,
                            systemImage: task.priority == priority ? "checkmark" : "flag",
                        )
                    }
                }
            } label: {
                PriorityFlag(task.priority.flagLevel)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
        .frame(minHeight: RowHeight.standard)
    }

    private func categoryRow(for task: TaskDTO) -> some View {
        HStack(spacing: Space.md) {
            propertyLabel("Category")
            Spacer(minLength: 0)
            Menu {
                Button {
                    patch(["categoryId": .null]) { $0.with(categoryId: .some(nil)) }
                } label: {
                    Label("None", systemImage: task.categoryId == nil ? "checkmark" : "circle.dashed")
                }
                ForEach(store.categories) { category in
                    Button {
                        patch(["categoryId": .string(category.id)]) { $0.with(categoryId: category.id) }
                    } label: {
                        Label(category.name, systemImage: task.categoryId == category.id ? "checkmark" : "tag")
                    }
                }
            } label: {
                if let category = store.category(for: task.categoryId) {
                    CategoryChip(category: category)
                } else {
                    Text("None")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
        .frame(minHeight: RowHeight.standard)
    }

    private func goalRow(for task: TaskDTO) -> some View {
        HStack(spacing: Space.md) {
            propertyLabel("Goal")
            Spacer(minLength: 0)
            Menu {
                Button {
                    patch(["goalId": .null]) { $0.with(goalId: .some(nil)) }
                } label: {
                    Label("None", systemImage: task.goalId == nil ? "checkmark" : "circle.dashed")
                }
                ForEach(store.goals) { goal in
                    Button {
                        patch(["goalId": .string(goal.id)]) { $0.with(goalId: goal.id) }
                    } label: {
                        Label(goal.title, systemImage: task.goalId == goal.id ? "checkmark" : "target")
                    }
                }
            } label: {
                if let title = store.goalTitle(for: task.goalId) {
                    GoalChip(title)
                } else {
                    Text("None")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
        .frame(minHeight: RowHeight.standard)
    }

    private var repeatsRow: some View {
        Button {
            showingRecurring = true
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
                Text("Repeats — edit the recurring task")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: RowHeight.standard)
    }

    // MARK: - Subtasks

    private func subtaskProgress(for task: TaskDTO) -> some View {
        let counted = task.subtasks.filter { $0.status != .cancelled }
        let done = counted.filter { $0.status == .done }.count
        let fraction = counted.isEmpty ? 0 : Double(done) / Double(counted.count)
        return VStack(alignment: .leading, spacing: Space.xs) {
            Text("\(done)/\(counted.count)")
                .font(.monoJ)
                .foregroundStyle(Color.textSecondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bgSubtle)
                    Capsule()
                        .fill(Color.success)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 3)
        }
        .padding(.vertical, Space.xs)
    }

    private func subtaskRow(_ subtask: TaskRowDTO) -> some View {
        HStack(spacing: Space.md) {
            Button {
                toggleSubtask(subtask)
            } label: {
                Image(systemName: subtask.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(subtask.status == .done ? Color.success : Color.textTertiary)
            }
            .buttonStyle(.plain)

            Text(subtask.title)
                .font(.bodyJ)
                .foregroundStyle(subtask.status == .done ? Color.textTertiary : Color.textPrimary)
                .strikethrough(subtask.status == .done, color: .textTertiary)

            Spacer(minLength: 0)
        }
        .frame(minHeight: RowHeight.standard)
    }

    private func addSubtaskRow(for task: TaskDTO) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: "plus")
                .font(.system(size: 14))
                .foregroundStyle(Color.textTertiary)
            TextField("Add subtask", text: $newSubtaskTitle)
                .textFieldStyle(.plain)
                .font(.bodyJ)
                .onSubmit {
                    addSubtask(to: task)
                }
        }
        .frame(minHeight: RowHeight.standard)
    }

    // MARK: - Mutations

    /// Applies `local` to the screen immediately and queues the equivalent
    /// absolute patch — absolute so replaying it stays correct.
    private func patch(_ body: JSONObject, local: (TaskDTO) -> TaskDTO) {
        guard let task else { return }
        let updated = local(task)
        apply(updated)
        errorMessage = nil
        store.patch(task, body, applying: updated)
    }

    private func saveTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task?.title else {
            titleDraft = task?.title ?? titleDraft
            return
        }
        patch(["title": .string(trimmed)]) { $0.with(title: trimmed) }
    }

    private func saveNotesIfChanged() {
        guard let task else { return }
        let trimmed = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = task.notes ?? ""
        guard trimmed != current else { return }
        patch(["notes": trimmed.isEmpty ? .null : .string(trimmed)]) { $0.with(notes: .some(trimmed.isEmpty ? nil : trimmed)) }
    }

    private func toggleComplete() {
        guard let task else { return }
        apply(task.with(status: task.status == .done ? .open : .done))
        errorMessage = nil
        store.toggleComplete(task)
    }

    private func toggleSubtask(_ subtask: TaskRowDTO) {
        guard let task else { return }
        let done = subtask.status == .done
        var updated = task
        updated.subtasks = task.subtasks.map {
            $0.id == subtask.id ? $0.with(status: done ? .open : .done) : $0
        }
        apply(updated)
        errorMessage = nil
        model.mutate(
            "POST",
            "/tasks/\(subtask.id)/\(done ? "uncomplete" : "complete")",
            entities: [.task, .score],
            label: "\"\(subtask.title)\"",
        )
    }

    private func addSubtask(to task: TaskDTO) {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = UUID().uuidString
        var updated = task
        updated.subtasks = task.subtasks + [.locallyCreated(id: id, title: trimmed, dueDate: task.dueDate, parentTaskId: task.id)]
        apply(updated)
        newSubtaskTitle = ""
        errorMessage = nil
        model.mutate(
            "POST",
            "/tasks",
            body: TaskCreateRequest(id: id, title: trimmed, dueDate: task.dueDate, parentTaskId: task.id),
            entities: [.task, .score],
            label: "\"\(trimmed)\"",
        )
    }

    private func deleteSubtask(_ subtask: TaskRowDTO) {
        guard let task else { return }
        var updated = task
        updated.subtasks = task.subtasks.filter { $0.id != subtask.id }
        apply(updated)
        errorMessage = nil
        model.mutate(
            "DELETE",
            "/tasks/\(subtask.id)",
            entities: [.task, .score],
            label: "\"\(subtask.title)\"",
        )
    }

    private func deleteTask() {
        guard let task else { return }
        store.delete(task)
        close()
    }

    private func deleteTemplate(_ templateId: String) {
        errorMessage = nil
        model.mutate(
            "DELETE",
            "/recurrence-templates/\(templateId)",
            entities: [.task],
            label: "the repeat rule",
        )
        close()
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    // MARK: - Date helpers

    private static func dayKey(from date: Date) -> String {
        DayKeyMath.dayFormatter.string(from: date)
    }

    private static func timeString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private static func timeDate(from string: String) -> Date {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = parts.first ?? 9
        components.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: components) ?? .now
    }
}
