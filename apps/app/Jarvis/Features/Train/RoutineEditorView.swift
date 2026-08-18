import DesignSystem
import JarvisAPI
import SwiftUI

/// Write or edit a routine: "Leg day", "Chest & Back", whatever the user
/// actually trains. Nothing here is generated or suggested — the whole feature
/// is that this list is theirs.
///
/// Layout note: the exercise lines are a card with the numbers stacked under
/// their captions, not a single inline row. Inline, "Sets × Reps to Reps @ kg"
/// needs more width than a sheet has, so the captions wrapped mid-word and the
/// fields collapsed. Stacked, every column keeps its own width at any size.
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

    /// One editable routine line. Numbers live as strings so a half-typed
    /// field is not silently rewritten to 0 while the user is still typing.
    private struct Line: Identifiable, Equatable {
        var id: String { exerciseId }
        let exerciseId: String
        let name: String
        let isBodyweight: Bool
        var sets: String
        var repsLow: String
        var repsHigh: String
        var weight: String
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
                    content
                }
            }
            .background(Color.bgCanvas)
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
        .frame(minWidth: 620, idealWidth: 660, minHeight: 620, idealHeight: 700)
        #endif
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                routineCard
                exercisesSection
                if let errorText {
                    Text(errorText)
                        .font(.subheadJ)
                        .foregroundStyle(Color.danger)
                }
                if let routineId {
                    Button("Delete routine", role: .destructive) {
                        Task {
                            await store.deleteRoutine(routineId)
                            dismiss()
                        }
                    }
                    .buttonStyle(.jarvisSecondary)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(PageMargin.standard)
        }
    }

    // MARK: - Routine

    private var routineCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Routine")

            HStack(spacing: Space.sm) {
                TextField("", text: $emoji, prompt: Text("💪"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 18))
                    .frame(width: 46, height: 36)
                    .background(
                        Color.bgSubtle,
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous),
                    )

                PromptField(prompt: "Name, like Leg day or Chest & Back", text: $name)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Space.md)
                    .frame(height: 36)
                    .background(
                        Color.bgSubtle,
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous),
                    )
            }

            ColorSwatchPicker(selection: $color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Exercises

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Exercises", subtitle: lines.isEmpty ? nil : "\(lines.count)") {
                Button("Add") { showExercisePicker = true }
                    .buttonStyle(.jarvisSoft)
            }

            if lines.isEmpty {
                Text("No exercises yet. Add the movements you do, in the order you do them.")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.md)
            } else {
                ForEach($lines) { $line in
                    lineCard($line)
                }
            }

            Button {
                showExercisePicker = true
            } label: {
                Label("Add exercise", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.jarvisSecondary)

            Text("Targets are a reminder, not a rule. During a workout you also see what you actually lifted last time.")
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lineCard(_ line: Binding<Line>) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Text(line.wrappedValue.name)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.sm)
                Button {
                    withJarvisAnimation {
                        lines.removeAll { $0.exerciseId == line.wrappedValue.exerciseId }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(line.wrappedValue.name)")
            }

            HStack(alignment: .bottom, spacing: Space.sm) {
                CaptionedField(caption: "Sets", prompt: "3", text: line.sets, width: 48)
                CaptionedField(caption: "Reps", prompt: "8", text: line.repsLow, width: 48)
                CaptionedField(caption: "to", prompt: "12", text: line.repsHigh, width: 48)
                Spacer(minLength: 0)
                CaptionedField(
                    caption: line.wrappedValue.isBodyweight ? "Added" : "Weight",
                    prompt: "0",
                    text: line.weight,
                    width: 66,
                    suffix: "kg",
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard(padding: Space.md)
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
                sets: String($0.targetSets),
                repsLow: $0.targetRepsLow.map(String.init) ?? "",
                repsHigh: $0.targetRepsHigh.map(String.init) ?? "",
                weight: $0.targetWeightKg.map(Format.weight) ?? "",
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
                    sets: "3",
                    repsLow: "8",
                    repsHigh: "12",
                    weight: "",
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
            let low = Int(line.repsLow.trimmingCharacters(in: .whitespaces))
            return RoutineExerciseInput(
                exerciseId: line.exerciseId,
                targetSets: max(1, Int(line.sets.trimmingCharacters(in: .whitespaces)) ?? 3),
                targetRepsLow: low,
                // An empty "to" field means a fixed rep count, not an open
                // range, so it mirrors the low end rather than going nil.
                targetRepsHigh: Int(line.repsHigh.trimmingCharacters(in: .whitespaces)) ?? low,
                targetWeightKg: Double(
                    line.weight.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: ",", with: "."),
                ),
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
