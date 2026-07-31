import DesignSystem
import JarvisAPI
import SwiftUI

/// The fields a task is born with. Doubles as the composer's working state,
/// the defaults a screen hands it, and the prefill for the full editor.
struct TaskDraft: Identifiable, Equatable {
    let id = UUID()
    var title: String = ""
    var dueDate: DayKey?
    var dueTime: String?
    var priority: TaskPriority = .medium
    var categoryId: String?

    static func == (lhs: TaskDraft, rhs: TaskDraft) -> Bool {
        lhs.title == rhs.title && lhs.dueDate == rhs.dueDate && lhs.dueTime == rhs.dueTime
            && lhs.priority == rhs.priority && lhs.categoryId == rhs.categoryId
    }
}

/// One-line task composer, TickTick-style: type, glance at the chips, hit
/// return. Return creates the task and leaves the field open with the same
/// date/priority/category, so a brain-dump is a run of returns rather than a
/// run of sheets — the old flow was tap +, wait for a sheet, fill a form, tap
/// Save, wait for it to dismiss.
///
/// The typed text is parsed live (`QuickAddParser`), so "gym tomorrow 7pm
/// #health" fills the chips by itself; touching a chip afterwards wins, until
/// the text says something new.
struct QuickAddComposer: View {
    let todayKey: DayKey
    let categories: [TaskCategoryDTO]
    /// What a fresh draft starts as — the screen's context (its day, its
    /// category filter) rather than a blank slate.
    var defaults: TaskDraft = TaskDraft()
    var placeholder: String = "Add a task"
    var collapsedTitle: String = "Add task"
    /// Collapsed ⇄ composing. A binding so the toolbar + and ⌘N can open it.
    @Binding var isActive: Bool
    var onCreate: (TaskCreateRequest) -> Void
    var onCreateCategory: (String) async -> TaskCategoryDTO?
    /// "More…" — hands the half-written draft to the full editor (notes,
    /// repeat) instead of throwing the typing away.
    var onOpenEditor: (TaskDraft) -> Void

    @State private var text = ""
    @State private var draft = TaskDraft()
    /// Previous parse, so the chips only move when the *typing* changed them.
    @State private var lastParse = QuickAddParse()
    @State private var showDatePicker = false
    @State private var showNewCategory = false
    @State private var newCategoryName = ""
    @FocusState private var focused: Bool

    private var trimmedTitle: String {
        QuickAddParser.parse(text, today: todayKey, categories: categories)
            .title
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if isActive {
                composer
            } else {
                collapsedButton
            }
        }
        .onChange(of: isActive, initial: true) { _, active in
            if active { begin() }
        }
        .alert("New category", isPresented: $showNewCategory) {
            TextField("Name", text: $newCategoryName)
            Button("Create") { createCategory() }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        } message: {
            Text("e.g. Work, Personal, Household")
        }
    }

    // MARK: - Collapsed

    private var collapsedButton: some View {
        Button {
            isActive = true
        } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                Text(collapsedTitle)
                    .font(.headlineJ)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.accentPrimary)
            .frame(minHeight: RowHeight.standard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Composing

    private var composer: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.md) {
                Image(systemName: "circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.textTertiary)

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.headlineJ)
                    .focused($focused)
                    .onSubmit(submit)
                    .onChange(of: text) { _, newValue in applyParse(newValue) }
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    #endif

                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(trimmedTitle.isEmpty ? Color.textTertiary : Color.accentPrimary)
                }
                .buttonStyle(.plain)
                .disabled(trimmedTitle.isEmpty)
                .accessibilityLabel("Add task")
            }

            HStack(spacing: Space.sm) {
                ScrollView(.horizontal) {
                    HStack(spacing: Space.sm) {
                        dateChip
                        priorityChip
                        categoryChip
                    }
                }
                .scrollIndicators(.hidden)

                // Icons, not words: on an iPhone the chip row is already
                // competing for the width.
                Button {
                    openEditor()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options")

                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.leading, 22 + Space.md)
        }
        .padding(.vertical, Space.xs)
        #if os(macOS)
        .onExitCommand { close() }
        #endif
    }

    // MARK: - Chips

    private var dueLabel: String {
        guard let dueDate = draft.dueDate else { return "No date" }
        let base = switch DayKeyMath.diffDays(todayKey, dueDate) {
        case 0: "Today"
        case 1: "Tomorrow"
        case 2...6: TaskDateLabels.weekdayLabel(for: dueDate).split(separator: " ").first.map(String.init) ?? dueDate
        default: DayKeyMath.shortLabel(for: dueDate)
        }
        guard let dueTime = draft.dueTime else { return base }
        return "\(base) \(dueTime)"
    }

    private var dateChip: some View {
        Menu {
            Button("Today") { setDue(todayKey) }
            Button("Tomorrow") { setDue(DayKeyMath.addDays(todayKey, 1)) }
            Button("Next week") { setDue(DayKeyMath.addDays(todayKey, 7)) }
            Button("Pick date & time…") { showDatePicker = true }
            Divider()
            Button("No date") {
                draft.dueDate = nil
                draft.dueTime = nil
            }
        } label: {
            chipBody(
                icon: "calendar",
                text: dueLabel,
                isSet: draft.dueDate != nil,
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Due \(dueLabel)")
        .datePickerPresentation(isPresented: $showDatePicker) {
            QuickDateSheet(todayKey: todayKey, dueDate: $draft.dueDate, dueTime: $draft.dueTime)
        }
    }

    private var priorityChip: some View {
        Menu {
            ForEach(TaskPriority.allCases.reversed(), id: \.self) { priority in
                Button {
                    draft.priority = priority
                } label: {
                    Label(
                        priority.flagLevel.label,
                        systemImage: draft.priority == priority ? "checkmark" : "flag",
                    )
                }
            }
        } label: {
            HStack(spacing: Space.xs) {
                PriorityFlag(draft.priority.flagLevel)
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 3)
            .background(Color.bgSubtle, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Priority \(draft.priority.flagLevel.label)")
    }

    private var selectedCategory: TaskCategoryDTO? {
        categories.first { $0.id == draft.categoryId }
    }

    private var categoryChip: some View {
        Menu {
            Button("None") { draft.categoryId = nil }
            ForEach(categories) { category in
                Button {
                    draft.categoryId = category.id
                } label: {
                    Label(category.name, systemImage: draft.categoryId == category.id ? "checkmark" : "tag")
                }
            }
            Divider()
            Button("New category…") {
                newCategoryName = ""
                showNewCategory = true
            }
        } label: {
            chipBody(
                icon: "tag",
                text: selectedCategory?.name ?? "Category",
                isSet: draft.categoryId != nil,
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Category \(selectedCategory?.name ?? "none")")
    }

    private func chipBody(icon: String, text: String, isSet: Bool) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.captionJ)
                .lineLimit(1)
        }
        .foregroundStyle(isSet ? Color.accentPrimary : Color.textSecondary)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 3)
        .background(isSet ? Color.accentSubtle : Color.bgSubtle, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 0.5))
    }

    // MARK: - Actions

    private func begin() {
        text = ""
        draft = defaults
        lastParse = QuickAddParse()
        focused = true
    }

    private func close() {
        text = ""
        focused = false
        isActive = false
    }

    private func setDue(_ dayKey: DayKey) {
        draft.dueDate = dayKey
    }

    /// Live parse: a field the typing set moves its chip, and deleting the
    /// phrase puts the chip back to the screen's default. Anything the parser
    /// stays quiet about is left exactly as the chips have it.
    private func applyParse(_ newValue: String) {
        let parse = QuickAddParser.parse(newValue, today: todayKey, categories: categories)
        defer { lastParse = parse }
        guard parse != lastParse else { return }

        if parse.dueDate != lastParse.dueDate {
            draft.dueDate = parse.dueDate ?? defaults.dueDate
        }
        if parse.dueTime != lastParse.dueTime {
            draft.dueTime = parse.dueTime ?? defaults.dueTime
        }
        if parse.priority != lastParse.priority {
            draft.priority = parse.priority ?? defaults.priority
        }
        if parse.categoryId != lastParse.categoryId {
            draft.categoryId = parse.categoryId ?? defaults.categoryId
        }
    }

    private func submit() {
        let title = trimmedTitle
        guard !title.isEmpty else { return }
        onCreate(
            TaskCreateRequest(
                id: UUID().uuidString,
                title: title,
                dueDate: draft.dueDate,
                dueTime: draft.dueTime,
                priority: draft.priority,
                categoryId: draft.categoryId,
            ),
        )
        // Stay open with the same chips — the next task is usually like the
        // one just added. Return resigns first responder on iOS, so focus has
        // to be taken back on the next tick or the keyboard drops.
        text = ""
        lastParse = QuickAddParse()
        Task { focused = true }
    }

    private func openEditor() {
        var prefill = draft
        prefill.title = trimmedTitle
        onOpenEditor(prefill)
        close()
    }

    private func createCategory() {
        let name = newCategoryName
        newCategoryName = ""
        Task {
            if let created = await onCreateCategory(name) {
                draft.categoryId = created.id
            }
        }
    }
}

// MARK: - Date & time picker

/// Sheet on iPhone (it has to clear the keyboard), popover on Mac.
private extension View {
    @ViewBuilder
    func datePickerPresentation(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> some View,
    ) -> some View {
        #if os(macOS)
        popover(isPresented: isPresented, arrowEdge: .bottom, content: content)
        #else
        sheet(isPresented: isPresented) {
            content()
                .presentationDetents([.medium, .large])
        }
        #endif
    }
}

private struct QuickDateSheet: View {
    let todayKey: DayKey
    @Binding var dueDate: DayKey?
    @Binding var dueTime: String?

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date = .now
    @State private var hasTime = false
    @State private var time: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            DatePicker("Due date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()

            Toggle("Time", isOn: $hasTime)
                .font(.subheadJ)
            if hasTime {
                DatePicker("At", selection: $time, displayedComponents: .hourAndMinute)
                    .font(.subheadJ)
            }

            HStack {
                Button("Clear") {
                    dueDate = nil
                    dueTime = nil
                    dismiss()
                }
                .buttonStyle(.jarvisGhost)
                Spacer(minLength: Space.md)
                Button("Done") { commit() }
                    .buttonStyle(.jarvisPrimary)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: 340)
        .background(Color.bgCanvas)
        .onAppear {
            date = dueDate.flatMap { DayKeyMath.date(from: $0) }
                ?? DayKeyMath.date(from: todayKey)
                ?? .now
            hasTime = dueTime != nil
            time = Self.date(fromTime: dueTime ?? "09:00")
        }
    }

    private func commit() {
        dueDate = DayKeyMath.dayFormatter.string(from: date)
        if hasTime {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            dueTime = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        } else {
            dueTime = nil
        }
        dismiss()
    }

    private static func date(fromTime string: String) -> Date {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = parts.first ?? 9
        components.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: components) ?? .now
    }
}
