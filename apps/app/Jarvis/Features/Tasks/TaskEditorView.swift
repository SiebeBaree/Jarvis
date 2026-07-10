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
    var onSaved: () async -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = true
    @State private var dueDate: Date = .now
    @State private var hasTime = false
    @State private var dueTime: Date = .now
    @State private var priority: TaskPriority = .medium
    @State private var goalId: String?
    @State private var repeats = false
    @State private var rule = RecurrenceRuleDTO(freq: "daily", interval: 1)
    @State private var isSaving = false
    @State private var errorMessage: String?

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

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadJ)
                            .foregroundStyle(Color.danger)
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
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: repeats) { _, isOn in
                // A template always needs a start date.
                if isOn { hasDueDate = true }
            }
            .onAppear {
                if let date = DayKeyMath.date(from: defaultDueDate) {
                    dueDate = date
                }
                dueTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
                titleFocused = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 540)
        #endif
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                let dayKey = DayKeyMath.dayFormatter.string(from: dueDate)
                let timeString = hasTime && hasDueDate ? Self.timeString(from: dueTime) : nil
                if repeats {
                    _ = try await model.api.createTemplate(
                        TemplateCreateRequest(
                            title: trimmed,
                            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                            priority: priority,
                            goalId: goalId,
                            dueTime: timeString,
                            rule: normalizedRule(),
                            startDate: dayKey,
                        ),
                    )
                } else {
                    _ = try await model.api.createTask(
                        TaskCreateRequest(
                            title: trimmed,
                            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                            dueDate: hasDueDate ? dayKey : nil,
                            dueTime: timeString,
                            priority: priority,
                            goalId: goalId,
                        ),
                    )
                }
                model.invalidateToday()
                await onSaved()
                dismiss()
            } catch {
                model.handle(error)
                errorMessage = error.localizedDescription
            }
        }
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
