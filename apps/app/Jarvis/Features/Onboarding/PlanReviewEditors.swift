import DesignSystem
import JarvisAPI
import SwiftUI

// MARK: - Row summaries

enum PlanDraftDisplay {
    static func summary(for habit: PlanHabitDTO) -> String {
        switch habit.type {
        case .daily: "Daily"
        case .multiDaily: "\(habit.targetReps)×/day"
        case .weeklyFrequency: "Weekly · \(habit.targetReps)×/wk"
        }
    }

    static func summary(for task: PlanTaskDTO) -> String {
        var parts = [priorityLabel(task.priority)]
        if let offset = task.dueOffsetDays {
            parts.append("day \(offset)")
        }
        return parts.joined(separator: " · ")
    }

    static func priorityLabel(_ priority: TaskPriority) -> String {
        switch priority {
        case .high: "P1"
        case .medium: "P2"
        case .low: "P3"
        }
    }
}

// MARK: - Vision edit sheet

struct VisionEditSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(Space.md)
                .background(Color.bgSurface)
                .navigationTitle("Edit Vision")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            text = draft
                            dismiss()
                        }
                    }
                }
        }
        .onAppear { draft = text }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 400)
        #endif
    }
}

// MARK: - Tactic edit sheet

struct TacticEditSheet: View {
    @State var title: String
    @State var fromWeek: Int
    @State var toWeek: Int
    let onSave: (String, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tactic") {
                    TextField("What will you do each week?", text: $title, axis: .vertical)
                        .font(.bodyJ)
                }
                Section("Weeks") {
                    Stepper("From week: \(fromWeek)", value: $fromWeek, in: 1...12)
                        .onChange(of: fromWeek) {
                            if toWeek < fromWeek { toWeek = fromWeek }
                        }
                    Stepper("To week: \(toWeek)", value: $toWeek, in: 1...12)
                        .onChange(of: toWeek) {
                            if fromWeek > toWeek { fromWeek = toWeek }
                        }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Tactic")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedTitle, fromWeek, toWeek)
                        dismiss()
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }
}

// MARK: - Habit edit sheet

struct HabitEditSheet: View {
    @State var name: String
    @State var type: HabitType
    @State private var timesPerDay: Int
    @State private var timesPerWeek: Int
    @State var plannedDays: Set<Int>
    let onSave: (String, HabitType, Int, [Int]) -> Void

    @Environment(\.dismiss) private var dismiss

    init(name: String, type: HabitType, targetReps: Int, plannedDays: Set<Int>, onSave: @escaping (String, HabitType, Int, [Int]) -> Void) {
        _name = State(initialValue: name)
        _type = State(initialValue: type)
        _timesPerDay = State(initialValue: type == .multiDaily ? max(targetReps, 2) : 2)
        _timesPerWeek = State(initialValue: type == .weeklyFrequency ? max(targetReps, 1) : 3)
        _plannedDays = State(initialValue: plannedDays)
        self.onSave = onSave
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var targetReps: Int {
        switch type {
        case .daily: 1
        case .multiDaily: timesPerDay
        case .weeklyFrequency: timesPerWeek
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Habit name", text: $name)
                        .font(.bodyJ)
                }
                Section {
                    Picker("Type", selection: $type) {
                        Text("Daily").tag(HabitType.daily)
                        Text("Per day").tag(HabitType.multiDaily)
                        Text("Weekly").tag(HabitType.weeklyFrequency)
                    }
                    .pickerStyle(.segmented)

                    if type == .multiDaily {
                        Stepper("Times per day: \(timesPerDay)", value: $timesPerDay, in: 2...10)
                    }
                    if type == .weeklyFrequency {
                        Stepper("Times per week: \(timesPerWeek)", value: $timesPerWeek, in: 1...7)
                        plannedDaysRow
                    }
                } header: {
                    Text("Type")
                } footer: {
                    if type == .weeklyFrequency {
                        Text("Suggested days (never penalized)")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Habit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let days = type == .weeklyFrequency ? plannedDays.sorted() : []
                        onSave(trimmedName, type, targetReps, days)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 380)
        #endif
    }

    private var plannedDaysRow: some View {
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return HStack(spacing: Space.sm) {
            ForEach(1...7, id: \.self) { day in
                let isOn = plannedDays.contains(day)
                Button {
                    if isOn {
                        plannedDays.remove(day)
                    } else {
                        plannedDays.insert(day)
                    }
                } label: {
                    Text(letters[day - 1])
                        .font(.captionJ)
                        .foregroundStyle(isOn ? .white : Color.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(
                            isOn ? Color.accentPrimary : Color.bgSubtle,
                            in: Circle(),
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Weekday \(day)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, Space.xs)
    }
}

// MARK: - Task edit sheet

struct TaskEditSheet: View {
    @State var title: String
    @State var priority: TaskPriority
    @State private var hasDueDay: Bool
    @State private var dueOffset: Int
    let onSave: (String, TaskPriority, Int?) -> Void

    @Environment(\.dismiss) private var dismiss

    init(title: String, priority: TaskPriority, dueOffsetDays: Int?, onSave: @escaping (String, TaskPriority, Int?) -> Void) {
        _title = State(initialValue: title)
        _priority = State(initialValue: priority)
        _hasDueDay = State(initialValue: dueOffsetDays != nil)
        _dueOffset = State(initialValue: dueOffsetDays ?? 7)
        self.onSave = onSave
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task title", text: $title, axis: .vertical)
                        .font(.bodyJ)
                }
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("P1").tag(TaskPriority.high)
                        Text("P2").tag(TaskPriority.medium)
                        Text("P3").tag(TaskPriority.low)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Due day", isOn: $hasDueDay)
                    if hasDueDay {
                        Stepper("Day \(dueOffset) of the block", value: $dueOffset, in: 0...84)
                    }
                } footer: {
                    Text("Counted from the block's start Monday.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedTitle, priority, hasDueDay ? dueOffset : nil)
                        dismiss()
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}
