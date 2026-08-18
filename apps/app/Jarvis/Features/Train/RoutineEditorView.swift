import DesignSystem
import JarvisAPI
import SwiftUI

/// Write or edit a routine: "Leg day", "Chest & Back", whatever the user
/// actually trains. Nothing here is generated or suggested — the whole feature
/// is that this list is theirs.
struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let store: WorkoutsStore
    /// nil = creating a new routine.
    let routineId: String?

    @State private var name = ""
    @State private var emoji = ""
    @State private var color: ItemColor = .rose
    @State private var lines: [Line] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var showExercisePicker = false
    @State private var didLoad = false

    /// One editable routine line. Reps are a range because that is how a
    /// program is written ("3 × 8-12"), and the two fields collapse to one
    /// number when they match.
    private struct Line: Identifiable, Equatable {
        var id: String { exerciseId }
        let exerciseId: String
        let name: String
        let isBodyweight: Bool
        var sets: Int
        var repsLow: Int?
        var repsHigh: Int?
        var weightKg: Double?
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .navigationTitle(routineId == nil ? "New routine" : "Edit routine")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Save", action: save).disabled(!canSave)
                    }
                }
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerView(store: store) { exercise in
                add(exercise)
            }
        }
        .task { await load() }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
    }

    private var form: some View {
        Form {
            Section("Routine") {
                HStack(spacing: Space.md) {
                    TextField("💪", text: $emoji)
                        .frame(width: 44)
                        .multilineTextAlignment(.center)
                    TextField("Leg day, Chest & Back, …", text: $name)
                }
                colorRow
            }

            Section {
                if lines.isEmpty {
                    Text("No exercises yet. Add the movements you do, in the order you do them.")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    ForEach($lines) { $line in
                        LineEditor(line: $line)
                    }
                    .onDelete { lines.remove(atOffsets: $0) }
                    .onMove { lines.move(fromOffsets: $0, toOffset: $1) }
                }

                Button {
                    showExercisePicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus.circle")
                }
            } header: {
                Text("Exercises")
            } footer: {
                Text("Targets are a reminder, not a rule. During a workout you will also see what you actually lifted last time.")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }

            if let errorText {
                Text(errorText)
                    .font(.subheadJ)
                    .foregroundStyle(Color.danger)
            }

            if let routineId {
                Section {
                    Button("Delete routine", role: .destructive) {
                        Task {
                            await store.deleteRoutine(routineId)
                            dismiss()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                ForEach(ItemColor.palette) { option in
                    Circle()
                        .fill(option.color)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.textPrimary, lineWidth: option.id == color.id ? 2 : 0)
                                .padding(-3),
                        )
                        .pressable(haptic: .light) { color = option }
                        .accessibilityLabel(option.displayName)
                }
            }
            .padding(.vertical, Space.xs)
        }
    }

    // MARK: - Line editor

    private struct LineEditor: View {
        @Binding var line: Line

        var body: some View {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(line.name)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: Space.sm) {
                    field("Sets", value: Binding(
                        get: { String(line.sets) },
                        set: { line.sets = max(1, Int($0) ?? 1) },
                    ), width: 46)

                    Text("×").foregroundStyle(Color.textTertiary)

                    field("Reps", value: Binding(
                        get: { line.repsLow.map(String.init) ?? "" },
                        set: { line.repsLow = Int($0) },
                    ), width: 46)

                    Text("-").foregroundStyle(Color.textTertiary)

                    field("to", value: Binding(
                        get: { line.repsHigh.map(String.init) ?? "" },
                        set: { line.repsHigh = Int($0) },
                    ), width: 46)

                    Spacer(minLength: 0)

                    if !line.isBodyweight {
                        field("kg", value: Binding(
                            get: { line.weightKg.map(Format.weight) ?? "" },
                            set: { line.weightKg = Double($0.replacingOccurrences(of: ",", with: ".")) },
                        ), width: 56)
                        Text("kg")
                            .font(.microJ)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .padding(.vertical, Space.xs)
        }

        private func field(_ placeholder: String, value: Binding<String>, width: CGFloat) -> some View {
            TextField(placeholder, text: value)
                .multilineTextAlignment(.center)
                .frame(width: width)
                .padding(.vertical, 5)
                .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }

    // MARK: - Load & save

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        await store.loadExercises()
        guard let routineId else { return }
        isLoading = true
        defer { isLoading = false }
        guard let detail = await store.routineDetail(routineId) else { return }
        name = detail.name
        emoji = detail.emoji ?? ""
        color = ItemColor.named(detail.colorHex)
        lines = detail.exercises.map {
            Line(
                exerciseId: $0.exerciseId,
                name: $0.name,
                isBodyweight: $0.isBodyweight,
                sets: $0.targetSets,
                repsLow: $0.targetRepsLow,
                repsHigh: $0.targetRepsHigh,
                weightKg: $0.targetWeightKg,
            )
        }
    }

    private func add(_ exercise: ExerciseDTO) {
        guard !lines.contains(where: { $0.exerciseId == exercise.id }) else { return }
        withJarvisAnimation {
            lines.append(
                Line(
                    exerciseId: exercise.id,
                    name: exercise.name,
                    isBodyweight: exercise.isBodyweight,
                    sets: 3,
                    repsLow: exercise.isBodyweight ? nil : 8,
                    repsHigh: exercise.isBodyweight ? nil : 12,
                    weightKg: nil,
                ),
            )
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorText = nil

        let inputs = lines.map { line in
            RoutineExerciseInput(
                exerciseId: line.exerciseId,
                targetSets: line.sets,
                targetRepsLow: line.repsLow,
                // An empty "to" field means a fixed rep count, not an open
                // range, so it mirrors the low end rather than going nil.
                targetRepsHigh: line.repsHigh ?? line.repsLow,
                targetWeightKg: line.weightKg,
            )
        }

        Task {
            let ok = await store.saveRoutine(
                id: routineId,
                name: trimmed,
                emoji: emoji.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                colorHex: color.hexString,
                exercises: inputs,
            )
            isSaving = false
            if ok {
                Haptics.play(.success)
                dismiss()
            } else {
                errorText = store.actionError ?? "Could not save. Try again."
            }
        }
    }
}
