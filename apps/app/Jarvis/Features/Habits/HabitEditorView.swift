import DesignSystem
import JarvisAPI
import SwiftUI

/// Habit editor. Name, icon, colour, frequency, target, planned days, area.
///
/// Rebuilt from a grouped `Form` into a designed sheet with a live preview of
/// the row you are about to create. The old version made you imagine the
/// result from a stack of labelled controls; this shows it, which is also the
/// fastest way to notice you picked the same colour as an existing habit.
///
/// Creating is local-first — the sheet closes the moment you tap Save and the
/// write drains from the outbox. Editing an existing habit still goes through
/// the queue too, so neither path blocks on the network.
struct HabitEditorView: View {
    enum Mode {
        case create(HabitDraft)
        case edit(HabitDTO)
    }

    let mode: Mode
    var store: HabitsStore?
    var onSaved: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var symbol: String
    @State private var colorHex: String
    @State private var areaId: String?
    @State private var type: HabitType
    @State private var timesPerDay: Int
    @State private var timesPerWeek: Int
    @State private var plannedDays: Set<Int>
    @State private var startDate: Date
    @State private var areas: [AreaDTO] = []
    @State private var errorMessage: String?
    @State private var showSymbolPicker = false
    @State private var showArchiveConfirm = false

    init(mode: Mode, store: HabitsStore? = nil, onSaved: (() -> Void)? = nil) {
        self.mode = mode
        self.store = store
        self.onSaved = onSaved
        switch mode {
        case .create(let draft):
            _name = State(initialValue: draft.name)
            _symbol = State(initialValue: draft.symbol)
            _colorHex = State(initialValue: draft.colorHex)
            _areaId = State(initialValue: nil)
            _type = State(initialValue: draft.type)
            _timesPerDay = State(initialValue: draft.type == .multiDaily ? draft.targetReps : 2)
            _timesPerWeek = State(initialValue: draft.type == .weeklyFrequency ? draft.targetReps : 3)
            _plannedDays = State(initialValue: [])
            _startDate = State(initialValue: .now)
        case .edit(let habit):
            _name = State(initialValue: habit.name)
            _symbol = State(initialValue: HabitDisplay.icon(for: habit))
            _colorHex = State(initialValue: HabitDisplay.color(for: habit).hexString)
            _areaId = State(initialValue: habit.areaId)
            _type = State(initialValue: habit.type)
            _timesPerDay = State(initialValue: habit.type == .multiDaily ? habit.targetReps : 2)
            _timesPerWeek = State(initialValue: habit.type == .weeklyFrequency ? habit.targetReps : 3)
            _plannedDays = State(initialValue: Set(habit.plannedDays))
            _startDate = State(initialValue: DayKeyMath.date(from: habit.startDate) ?? .now)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var color: ItemColor { ItemColor.named(colorHex) }

    private var targetReps: Int {
        switch type {
        case .daily: 1
        case .multiDaily: timesPerDay
        case .weeklyFrequency: timesPerWeek
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    preview
                    identityCard
                    frequencyCard
                    if type == .weeklyFrequency {
                        plannedDaysCard
                    }
                    optionsCard
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadJ)
                            .foregroundStyle(Color.danger)
                    }
                    if isEditing {
                        archiveButton
                    }
                }
                .padding(PageMargin.standard)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color.bgCanvas)
            .navigationTitle(isEditing ? "Edit habit" : "New habit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .font(.headlineJ)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 600)
        #endif
        .sheet(isPresented: $showSymbolPicker) {
            SymbolPickerSheet(selection: $symbol, tint: color)
        }
        .task { await loadAreas() }
    }

    // MARK: - Preview

    /// The row as it will appear in the list.
    private var preview: some View {
        HStack(spacing: Space.md) {
            IconTile(symbol: symbol, color: color, size: TileSize.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(trimmedName.isEmpty ? "New habit" : trimmedName)
                    .font(.title3J)
                    .foregroundStyle(trimmedName.isEmpty ? Color.textTertiary : Color.textPrimary)
                    .lineLimit(1)
                Text(frequencyCaption)
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Space.sm)
            if type == .daily {
                CheckCircle(isOn: true, tint: color.color, size: 28) {}
                    .allowsHitTesting(false)
            } else {
                CountRing(done: max(targetReps - 1, 0), target: targetReps, tint: color.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
        .jarvisAnimation(Motion.standard, value: colorHex)
        .jarvisAnimation(Motion.standard, value: targetReps)
    }

    private var frequencyCaption: String {
        switch type {
        case .daily: "Every day"
        case .multiDaily: "\(timesPerDay) times a day"
        case .weeklyFrequency: "\(timesPerWeek) times a week"
        }
    }

    // MARK: - Cards

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            TextField("Habit name", text: $name)
                .font(.headlineJ)
                .textFieldStyle(.plain)
                .padding(.horizontal, Space.md)
                .frame(height: 44)
                .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

            HStack(spacing: Space.md) {
                Button {
                    showSymbolPicker = true
                } label: {
                    HStack(spacing: Space.sm) {
                        IconTile(symbol: symbol, color: color, size: TileSize.small)
                        Text("Icon").font(.subheadStrongJ).foregroundStyle(Color.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.horizontal, Space.md)
                    .frame(height: 40)
                    .background(Color.bgSubtle, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }

            ColorPickerRow(selection: $colorHex)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private var frequencyCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("How often")

            ChipPicker(
                [HabitType.daily, .multiDaily, .weeklyFrequency],
                selection: $type,
                fillsWidth: true,
            ) { option in
                switch option {
                case .daily: "Daily"
                case .multiDaily: "Per day"
                case .weeklyFrequency: "Per week"
                }
            }
            .disabled(isEditing)
            .opacity(isEditing ? 0.5 : 1)

            switch type {
            case .daily:
                caption("Once a day. A simple check keeps the streak alive.")
            case .multiDaily:
                stepper(
                    label: "Times a day",
                    value: $timesPerDay,
                    range: 2...10,
                )
                caption("Partial reps earn partial credit. 1 of 2 is 50%.")
            case .weeklyFrequency:
                stepper(
                    label: "Times a week",
                    value: $timesPerWeek,
                    range: 1...7,
                )
                caption("Only the weekly total counts. Swap days freely.")
            }

            if isEditing {
                caption("The frequency type is locked. Changing it would rewrite this habit's history.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    /// A row of segmented number buttons instead of a `Stepper`: the target is
    /// almost always a small number, and tapping "8" directly beats tapping
    /// "+" six times.
    private func stepper(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(label)
                .font(.subheadStrongJ)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: Space.xs) {
                ForEach(Array(range), id: \.self) { number in
                    let isOn = value.wrappedValue == number
                    Button {
                        Haptics.play(.light)
                        withJarvisAnimation(Motion.quick) { value.wrappedValue = number }
                    } label: {
                        Text("\(number)")
                            .font(.monoJ)
                            .foregroundStyle(isOn ? .white : Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(isOn ? color.color : Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var plannedDaysCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Suggested days", subtitle: "Never penalised. Only the weekly total counts")
            let letters = ["M", "T", "W", "T", "F", "S", "S"]
            HStack(spacing: Space.xs) {
                ForEach(1...7, id: \.self) { day in
                    let isOn = plannedDays.contains(day)
                    Button {
                        Haptics.play(.light)
                        withJarvisAnimation(Motion.quick) {
                            if isOn { plannedDays.remove(day) } else { plannedDays.insert(day) }
                        }
                    } label: {
                        Text(letters[day - 1])
                            .font(.captionJ)
                            .foregroundStyle(isOn ? .white : Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(isOn ? color.color : Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Weekday \(day)")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if !areas.isEmpty {
                HStack {
                    Text("Area").font(.subheadStrongJ).foregroundStyle(Color.textSecondary)
                    Spacer()
                    Picker("Area", selection: $areaId) {
                        Text("None").tag(String?.none)
                        ForEach(areas) { area in
                            Text(area.name).tag(String?.some(area.id))
                        }
                    }
                    .labelsHidden()
                }
            }
            if !isEditing {
                HStack {
                    Text("Start date").font(.subheadStrongJ).foregroundStyle(Color.textSecondary)
                    Spacer()
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
        .opacity(areas.isEmpty && isEditing ? 0 : 1)
    }

    private var archiveButton: some View {
        Button("Archive habit", role: .destructive) {
            showArchiveConfirm = true
        }
        .buttonStyle(.jarvisSecondary)
        .frame(maxWidth: .infinity)
        .confirmationDialog("Archive this habit?", isPresented: $showArchiveConfirm) {
            Button("Archive", role: .destructive) { archive() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It stops counting from today. All history is kept.")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.subheadJ)
            .foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func loadAreas() async {
        if let response = try? await model.api.areas() {
            areas = response.areas.filter { $0.archivedAt == nil }
        }
    }

    private func save() {
        switch mode {
        case .create:
            let request = HabitCreateRequest(
                name: trimmedName,
                icon: symbol,
                colorHex: colorHex,
                type: type,
                targetReps: targetReps,
                plannedDays: type == .weeklyFrequency ? plannedDays.sorted() : nil,
                areaId: areaId,
                startDate: DayKeyMath.dayFormatter.string(from: startDate),
            )
            if let store {
                store.create(request)
            } else {
                // No store in context (opened from Today): fall back to a
                // queued write, which still never blocks the UI.
                model.mutate("POST", "/habits", body: request, entities: [.habit, .score], label: request.name)
            }
        case .edit(let habit):
            var patch: JSONObject = [
                "name": .string(trimmedName),
                "icon": .string(symbol),
                "colorHex": .string(colorHex),
                "targetReps": .int(targetReps),
                "areaId": areaId.map { .string($0) } ?? .null,
            ]
            if type == .weeklyFrequency {
                patch["plannedDays"] = .array(plannedDays.sorted().map { .int($0) })
            }
            model.mutate(
                "PATCH",
                "/habits/\(habit.id)",
                body: patch,
                entities: [.habit, .score],
                label: trimmedName,
            )
        }
        Haptics.play(.success)
        onSaved?()
        dismiss()
    }

    private func archive() {
        guard case .edit(let habit) = mode else { return }
        if let store {
            store.archive(habit)
        } else {
            model.mutate("POST", "/habits/\(habit.id)/archive", entities: [.habit, .score], label: habit.name)
        }
        onSaved?()
        dismiss()
    }
}
