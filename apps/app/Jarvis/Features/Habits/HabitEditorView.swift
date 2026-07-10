import DesignSystem
import JarvisAPI
import SwiftUI

/// Habit editor sheet (§B3): name, icon grid, area, type (locked when
/// editing), per-type targets, planned days, start date (create only),
/// archive section (edit only).
struct HabitEditorView: View {
    enum Mode {
        case create
        case edit(HabitDTO)
    }

    let mode: Mode
    var onSaved: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var icon: String
    @State private var areaId: String?
    @State private var type: HabitType
    @State private var timesPerDay: Int
    @State private var timesPerWeek: Int
    @State private var plannedDays: Set<Int>
    @State private var startDate: Date
    @State private var areas: [AreaDTO] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showArchiveConfirm = false

    init(mode: Mode, onSaved: (() -> Void)? = nil) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _icon = State(initialValue: "circle")
            _areaId = State(initialValue: nil)
            _type = State(initialValue: .daily)
            _timesPerDay = State(initialValue: 2)
            _timesPerWeek = State(initialValue: 3)
            _plannedDays = State(initialValue: [])
            _startDate = State(initialValue: .now)
        case .edit(let habit):
            _name = State(initialValue: habit.name)
            _icon = State(initialValue: HabitDisplay.icon(for: habit))
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

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                iconSection
                areaSection
                typeSection
                if !isEditing {
                    Section {
                        DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    }
                }
                saveSection
                if isEditing {
                    archiveSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Habit" : "New Habit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 560)
        #endif
        .task { await loadAreas() }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Name") {
            TextField("Habit name", text: $name)
                .font(.bodyJ)
        }
    }

    private var iconSection: some View {
        Section("Icon") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.sm), count: 8), spacing: Space.sm) {
                ForEach(Self.icons, id: \.self) { symbol in
                    Button {
                        icon = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(icon == symbol ? Color.accentPrimary : Color.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(
                                icon == symbol ? Color.accentSubtle : Color.clear,
                                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous),
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                }
            }
            .padding(.vertical, Space.xs)
        }
    }

    private var areaSection: some View {
        Section("Area") {
            Picker("Area", selection: $areaId) {
                Text("None").tag(String?.none)
                ForEach(areas) { area in
                    Text(area.name).tag(String?.some(area.id))
                }
            }
        }
    }

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $type) {
                Text("Daily").tag(HabitType.daily)
                Text("Per day").tag(HabitType.multiDaily)
                Text("Weekly").tag(HabitType.weeklyFrequency)
            }
            .pickerStyle(.segmented)
            .disabled(isEditing)

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
            if isEditing {
                Text("The type is locked — changing it would corrupt this habit's history.")
            } else if type == .weeklyFrequency {
                Text("Suggested days (never penalized)")
            }
        }
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

    private var saveSection: some View {
        Section {
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            }
            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.jarvisPrimary)
            .disabled(trimmedName.isEmpty || isSaving)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var archiveSection: some View {
        Section {
            Button("Archive habit", role: .destructive) {
                showArchiveConfirm = true
            }
            .confirmationDialog(
                "Archive this habit?",
                isPresented: $showArchiveConfirm,
            ) {
                Button("Archive", role: .destructive) {
                    Task { await archive() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It stops counting from today. All history is kept.")
            }
        } footer: {
            Text("Archiving keeps the habit's history and calendar.")
        }
    }

    // MARK: - Actions

    private func loadAreas() async {
        if let response = try? await model.api.areas() {
            areas = response.areas.filter { $0.archivedAt == nil }
        }
    }

    private var targetReps: Int {
        switch type {
        case .daily: 1
        case .multiDaily: timesPerDay
        case .weeklyFrequency: timesPerWeek
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            switch mode {
            case .create:
                let request = HabitCreateRequest(
                    name: trimmedName,
                    icon: icon,
                    type: type,
                    targetReps: targetReps,
                    plannedDays: type == .weeklyFrequency ? plannedDays.sorted() : nil,
                    areaId: areaId,
                    startDate: DayKeyMath.dayFormatter.string(from: startDate),
                )
                _ = try await model.api.createHabit(request)
            case .edit(let habit):
                var patch: JSONObject = [
                    "name": .string(trimmedName),
                    "icon": .string(icon),
                    "targetReps": .int(targetReps),
                    "areaId": areaId.map { .string($0) } ?? .null,
                ]
                if type == .weeklyFrequency {
                    patch["plannedDays"] = .array(plannedDays.sorted().map { .int($0) })
                }
                _ = try await model.api.patchHabit(id: habit.id, patch)
            }
            model.invalidateToday()
            onSaved?()
            dismiss()
        } catch {
            model.handle(error)
            errorMessage = TodayStore.message(for: error)
        }
    }

    private func archive() async {
        guard case .edit(let habit) = mode else { return }
        do {
            _ = try await model.api.archiveHabit(id: habit.id)
            model.invalidateToday()
            onSaved?()
            dismiss()
        } catch {
            model.handle(error)
            errorMessage = TodayStore.message(for: error)
        }
    }

    // MARK: - Curated SF Symbols

    static let icons: [String] = [
        "dumbbell.fill", "figure.run", "figure.walk", "figure.strengthtraining.traditional",
        "figure.mind.and.body", "figure.pool.swim", "bicycle", "flame.fill",
        "drop.fill", "fork.knife", "carrot.fill", "cup.and.saucer.fill",
        "pills.fill", "cross.case.fill", "bed.double.fill", "alarm.fill",
        "sun.max.fill", "moon.fill", "moon.stars.fill", "leaf.fill",
        "book.fill", "books.vertical.fill", "graduationcap.fill", "brain.head.profile",
        "pencil", "text.book.closed.fill", "laptopcomputer", "briefcase.fill",
        "dollarsign.circle.fill", "chart.line.uptrend.xyaxis", "checklist", "calendar",
        "phone.fill", "message.fill", "person.2.fill", "heart.fill",
        "face.smiling", "comb.fill", "shower.fill", "mouth.fill",
        "hands.and.sparkles.fill", "music.note", "camera.fill", "paintbrush.fill",
    ]
}
