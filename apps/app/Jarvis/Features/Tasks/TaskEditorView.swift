import DesignSystem
import JarvisAPI
import SwiftUI

/// New-task sheet. With "Repeat" on it creates a recurrence template
/// (startDate = the chosen due date) instead of a one-off task.
struct TaskEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let goals: [GoalDTO]
    let defaultDueDate: String
    /// Prefills the title field (quick-add "More…" hands off the typed text).
    var initialTitle: String? = nil
    /// Receives the fully-formed create request (with its client-generated
    /// id) so the calling list can show the row before it is sent.
    var onCreate: (TaskCreateRequest) -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = true
    @State private var dueDate: Date = .now
    @State private var hasTime = false
    @State private var dueTime: Date = .now
    @State private var priority: TaskPriority = .medium
    @State private var goalId: String?
    @State private var categories: [TaskCategoryDTO] = []
    @State private var categoryId: String?
    @State private var showNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var repeats = false
    @State private var rule = RecurrenceRuleDTO(freq: "daily", interval: 1)

    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($titleFocused)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Toggle(repeats ? "Starts" : "Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker(
                            repeats ? "Start date" : "Date",
                            selection: $dueDate,
                            displayedComponents: .date,
                        )
                        Toggle("Time", isOn: $hasTime)
                        if hasTime {
                            DatePicker("At", selection: $dueTime, displayedComponents: .hourAndMinute)
                        }
                    }
                }

                Section {
                    Picker("Priority", selection: $priority) {
                        Text("P1 High").tag(TaskPriority.high)
                        Text("P2 Medium").tag(TaskPriority.medium)
                        Text("P3 Low").tag(TaskPriority.low)
                    }
                    .pickerStyle(.segmented)

                    Picker("Category", selection: $categoryId) {
                        Text("None").tag(String?.none)
                        ForEach(categories) { category in
                            Text(categoryLabel(category)).tag(Optional(category.id))
                        }
                    }
                    Button("New category…") {
                        newCategoryName = ""
                        showNewCategoryAlert = true
                    }
                    .font(.subheadJ)
                    .foregroundStyle(Color.accentPrimary)

                    Picker("Goal", selection: $goalId) {
                        Text("None").tag(String?.none)
                        ForEach(goals) { goal in
                            Text(goal.title).tag(Optional(goal.id))
                        }
                    }
                }

                Section {
                    Toggle("Repeat", isOn: $repeats)
                    if repeats {
                        RecurrenceRuleEditor(rule: $rule, defaultWeekday: isoWeekday(of: dueDate))
                    }
                } footer: {
                    if repeats {
                        Text("Saving creates a recurring task starting on the chosen date.")
                            .font(.captionJ)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

            }
            .formStyle(.grouped)
            .navigationTitle("New task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: repeats) { _, isOn in
                // A template always needs a start date.
                if isOn { hasDueDate = true }
            }
            .onAppear {
                if let initialTitle, !initialTitle.isEmpty {
                    title = initialTitle
                }
                if let date = DayKeyMath.date(from: defaultDueDate) {
                    dueDate = date
                }
                dueTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
                titleFocused = true
            }
            .task {
                if let response = try? await model.api.taskCategories() {
                    categories = response.categories
                }
            }
            .alert("New category", isPresented: $showNewCategoryAlert) {
                TextField("Name", text: $newCategoryName)
                Button("Create") { createCategory() }
                Button("Cancel", role: .cancel) { newCategoryName = "" }
            } message: {
                Text("e.g. Work, Personal, Household")
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 540)
        #endif
    }

    private func categoryLabel(_ category: TaskCategoryDTO) -> String {
        if let emoji = category.emoji, !emoji.isEmpty {
            return "\(emoji) \(category.name)"
        }
        return category.name
    }

    private func createCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        newCategoryName = ""
        guard !trimmed.isEmpty else { return }
        Task {
            guard let created = try? await model.api.createTaskCategory(
                TaskCategoryCreateRequest(
                    name: trimmed,
                    colorHex: CategoryPalette.next(after: categories.count),
                ),
            ) else { return }
            categories.append(created)
            categoryId = created.id
            model.invalidate([.category])
        }
    }

    /// Closes immediately and hands the write to the offline queue — the
    /// sheet used to sit open for a create round-trip plus a list refetch.
    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let dayKey = DayKeyMath.dayFormatter.string(from: dueDate)
        let timeString = hasTime && hasDueDate ? Self.timeString(from: dueTime) : nil

        if repeats {
            // A template materializes server-side into dated tasks, so there
            // is no local row to show — but the call still need not be awaited.
            model.mutate(
                "POST",
                "/recurrence-templates",
                body: TemplateCreateRequest(
                    title: trimmed,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                    priority: priority,
                    goalId: goalId,
                    categoryId: categoryId,
                    dueTime: timeString,
                    rule: normalizedRule(),
                    startDate: dayKey,
                ),
                entities: [.task, .score],
                label: "\"\(trimmed)\"",
            )
        } else {
            onCreate(
                TaskCreateRequest(
                    id: UUID().uuidString,
                    title: trimmed,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                    dueDate: hasDueDate ? dayKey : nil,
                    dueTime: timeString,
                    priority: priority,
                    goalId: goalId,
                    categoryId: categoryId,
                ),
            )
        }
        dismiss()
    }

    /// Keep only the fields relevant to the chosen frequency.
    private func normalizedRule() -> RecurrenceRuleDTO {
        var normalized = rule
        switch normalized.freq {
        case "weekly":
            let weekdays = (normalized.byWeekday ?? []).isEmpty
                ? [isoWeekday(of: dueDate)]
                : normalized.byWeekday!
            normalized.byWeekday = weekdays.sorted()
            normalized.byMonthDay = nil
        case "monthly":
            normalized.byWeekday = nil
            if normalized.byMonthDay == nil {
                normalized.byMonthDay = Calendar.current.component(.day, from: dueDate)
            }
        default:
            normalized.byWeekday = nil
            normalized.byMonthDay = nil
        }
        return normalized
    }

    private func isoWeekday(of date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date) // 1 = Sunday
        return weekday == 1 ? 7 : weekday - 1
    }

    private static func timeString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
