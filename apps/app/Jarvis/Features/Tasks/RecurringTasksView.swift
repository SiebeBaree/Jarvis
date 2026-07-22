import DesignSystem
import JarvisAPI
import SwiftUI

/// List of recurrence templates: rule summary, next occurrence, pause/resume,
/// delete, and a tap-to-edit sheet.
struct RecurringTasksView: View {
    @Environment(AppModel.self) private var model

    @State private var state: LoadState<[RecurrenceTemplateDTO]> = .idle
    @State private var goals: [GoalDTO] = []
    @State private var categories: [TaskCategoryDTO] = []
    @State private var editing: RecurrenceTemplateDTO?
    @State private var pendingDelete: RecurrenceTemplateDTO?
    @State private var actionError: String?

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: Space.md) {
                    Text(message)
                        .font(.subheadJ)
                        .foregroundStyle(Color.danger)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await fetch() }
                    }
                    .buttonStyle(.jarvisSecondary)
                }
                .padding(PageMargin.standard)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .loaded(let templates):
                if templates.isEmpty {
                    VStack(spacing: Space.md) {
                        Text("No recurring tasks yet")
                            .font(.bodyJ)
                            .foregroundStyle(Color.textSecondary)
                        Text("Turn on Repeat when creating a task.")
                            .font(.subheadJ)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    templateList(templates)
                }
            }
        }
        #if os(macOS)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        #endif
        .background(Color.bgCanvas)
        .navigationTitle("Recurring tasks")
        .sheet(item: $editing) { template in
            TemplateEditorSheet(template: template, goals: goals, categories: categories) {
                await fetch()
            }
        }
        .confirmationDialog(
            "Delete recurring task",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } },
            ),
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) {
                if let template = pendingDelete {
                    Task { await delete(template) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Future occurrences will no longer be created. Existing tasks stay.")
        }
        .task {
            await fetch()
            if let response = try? await model.api.goals() {
                goals = response.goals
            }
            if let response = try? await model.api.taskCategories() {
                categories = response.categories
            }
        }
    }

    private func templateList(_ templates: [RecurrenceTemplateDTO]) -> some View {
        List {
            if let actionError {
                Text(actionError)
                    .font(.subheadJ)
                    .foregroundStyle(Color.danger)
                    .listRowBackground(Color.bgCanvas)
                    .listRowSeparator(.hidden)
            }
            ForEach(templates) { template in
                row(for: template)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await fetch() }
    }

    private func row(for template: RecurrenceTemplateDTO) -> some View {
        let isPaused = template.pausedAt != nil
        return HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.sm) {
                    Text(template.title)
                        .font(.headlineJ)
                        .foregroundStyle(isPaused ? Color.textTertiary : Color.textPrimary)
                        .lineLimit(2)
                    if isPaused {
                        TagChip("Paused")
                    }
                }
                HStack(spacing: Space.sm) {
                    Text(template.rule.summaryText)
                        .font(.subheadJ)
                        .foregroundStyle(Color.textSecondary)
                    if !isPaused,
                       let next = RecurrenceMath.nextOccurrence(of: template, onOrAfter: todayKey) {
                        Text("Next: \(TaskDateLabels.shortLabel(for: next))")
                            .font(.subheadJ)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            Spacer(minLength: Space.sm)
            PriorityFlag(template.priority.flagLevel, showsLabel: false)
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = template }
        .frame(minHeight: RowHeight.standard)
        .listRowBackground(Color.bgCanvas)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = template
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                Task { await setPaused(!isPaused, template: template) }
            } label: {
                Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play" : "pause")
            }
            .tint(.textSecondary)
        }
        .contextMenu {
            Button(isPaused ? "Resume" : "Pause") {
                Task { await setPaused(!isPaused, template: template) }
            }
            Button("Delete", role: .destructive) {
                pendingDelete = template
            }
        }
    }

    private var todayKey: String {
        DayKeyMath.todayKey(boundaryHour: model.settings?.dayBoundaryHour ?? 3)
    }

    // MARK: - Data

    private func fetch() async {
        if state.value == nil { state = .loading }
        do {
            let response = try await model.api.templates()
            state = .loaded(response.templates)
        } catch {
            model.handle(error)
            state = .failed(error.localizedDescription)
        }
    }

    private func setPaused(_ paused: Bool, template: RecurrenceTemplateDTO) async {
        do {
            _ = try await model.api.patchTemplate(id: template.id, ["paused": .bool(paused)])
            actionError = nil
            model.invalidateToday()
            await fetch()
        } catch {
            model.handle(error)
            actionError = error.localizedDescription
        }
    }

    private func delete(_ template: RecurrenceTemplateDTO) async {
        do {
            _ = try await model.api.deleteTemplate(id: template.id)
            actionError = nil
            pendingDelete = nil
            model.invalidateToday()
            await fetch()
        } catch {
            model.handle(error)
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Template edit sheet

private struct TemplateEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let template: RecurrenceTemplateDTO
    let goals: [GoalDTO]
    let categories: [TaskCategoryDTO]
    var onSaved: () async -> Void

    @State private var title = ""
    @State private var priority: TaskPriority = .medium
    @State private var goalId: String?
    @State private var categoryId: String?
    @State private var hasTime = false
    @State private var dueTime: Date = .now
    @State private var showInReviewWeek = false
    @State private var rule = RecurrenceRuleDTO(freq: "daily", interval: 1)
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
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
                            Text(category.name).tag(Optional(category.id))
                        }
                    }

                    Picker("Goal", selection: $goalId) {
                        Text("None").tag(String?.none)
                        ForEach(goals) { goal in
                            Text(goal.title).tag(Optional(goal.id))
                        }
                    }

                    Toggle("Time", isOn: $hasTime)
                    if hasTime {
                        DatePicker("At", selection: $dueTime, displayedComponents: .hourAndMinute)
                    }

                    Toggle("Show during review week", isOn: $showInReviewWeek)
                }

                Section {
                    RecurrenceRuleEditor(rule: $rule)
                } header: {
                    Text("Repeat")
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
            .navigationTitle("Edit recurring task")
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
            .onAppear {
                title = template.title
                priority = template.priority
                goalId = template.goalId
                categoryId = template.categoryId
                showInReviewWeek = template.showInReviewWeek ?? false
                rule = template.rule
                if let time = template.dueTime {
                    hasTime = true
                    let parts = time.split(separator: ":").compactMap { Int($0) }
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
                    components.hour = parts.first ?? 9
                    components.minute = parts.count > 1 ? parts[1] : 0
                    dueTime = Calendar.current.date(from: components) ?? .now
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 480)
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
                var patch: JSONObject = [
                    "title": .string(trimmed),
                    "priority": .string(priority.rawValue),
                    "goalId": goalId.map { .string($0) } ?? .null,
                    "categoryId": categoryId.map { .string($0) } ?? .null,
                    "rule": rule.jsonValue,
                    "showInReviewWeek": .bool(showInReviewWeek),
                ]
                if hasTime {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: dueTime)
                    patch["dueTime"] = .string(
                        String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0),
                    )
                } else {
                    patch["dueTime"] = .null
                }
                _ = try await model.api.patchTemplate(id: template.id, patch)
                model.invalidateToday()
                await onSaved()
                dismiss()
            } catch {
                model.handle(error)
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Rule → JSON and next-occurrence math

extension RecurrenceRuleDTO {
    var jsonValue: JSONValue {
        var object: [String: JSONValue] = [
            "freq": .string(freq),
            "interval": .int(max(1, interval)),
        ]
        if let byWeekday, !byWeekday.isEmpty {
            object["byWeekday"] = .array(byWeekday.map(JSONValue.int))
        }
        if let byMonthDay {
            object["byMonthDay"] = .int(byMonthDay)
        }
        return .object(object)
    }
}

/// Client-side mirror of the server's occurrence expansion, used only for the
/// "Next: Aug 1" caption. The server remains the source of truth.
enum RecurrenceMath {
    static func nextOccurrence(of template: RecurrenceTemplateDTO, onOrAfter dayKey: String) -> String? {
        guard let start = DayKeyMath.date(from: template.startDate) else { return nil }
        let fromKey = max(dayKey, template.startDate)
        guard var cursor = DayKeyMath.date(from: fromKey) else { return nil }
        let calendar = Calendar.current
        let interval = max(1, template.rule.interval)

        for _ in 0..<400 {
            let cursorKey = DayKeyMath.dayFormatter.string(from: cursor)
            if let endDate = template.endDate, cursorKey > endDate { return nil }
            if matches(rule: template.rule, interval: interval, start: start, candidate: cursor, calendar: calendar) {
                return cursorKey
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
        }
        return nil
    }

    private static func matches(
        rule: RecurrenceRuleDTO,
        interval: Int,
        start: Date,
        candidate: Date,
        calendar: Calendar,
    ) -> Bool {
        switch rule.freq {
        case "weekly":
            let weekday = isoWeekday(of: candidate, calendar: calendar)
            let weekdays = rule.byWeekday ?? [isoWeekday(of: start, calendar: calendar)]
            guard weekdays.contains(weekday) else { return false }
            let weeks = weeksBetween(start, candidate, calendar: calendar)
            return weeks >= 0 && weeks % interval == 0
        case "monthly":
            let day = calendar.component(.day, from: candidate)
            let target = rule.byMonthDay ?? calendar.component(.day, from: start)
            let daysInMonth = calendar.range(of: .day, in: .month, for: candidate)?.count ?? 31
            guard day == min(target, daysInMonth) else { return false }
            let months = calendar.dateComponents(
                [.month],
                from: calendar.startOfDay(for: start),
                to: calendar.startOfDay(for: candidate),
            ).month ?? 0
            return months >= 0 && months % interval == 0
        default:
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: start),
                to: calendar.startOfDay(for: candidate),
            ).day ?? 0
            return days >= 0 && days % interval == 0
        }
    }

    private static func isoWeekday(of date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        return weekday == 1 ? 7 : weekday - 1
    }

    private static func weeksBetween(_ start: Date, _ end: Date, calendar: Calendar) -> Int {
        let startMonday = mondayOfWeek(containing: start, calendar: calendar)
        let endMonday = mondayOfWeek(containing: end, calendar: calendar)
        let days = calendar.dateComponents([.day], from: startMonday, to: endMonday).day ?? 0
        return days / 7
    }

    private static func mondayOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let offset = isoWeekday(of: date, calendar: calendar) - 1
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }
}
