import DesignSystem
import JarvisAPI
import SwiftUI

/// Pick an exercise, or create one by typing its name.
///
/// Creating is deliberately the same gesture as searching: the first time you
/// do an exercise you type it, and every time after that the same typing finds
/// it. That is also why the server treats a duplicate name as a reuse — one
/// movement, one history.
struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let store: WorkoutsStore
    let onPick: (ExerciseDTO) -> Void

    @State private var query = ""
    @State private var isCreating = false
    @FocusState private var searchFocused: Bool

    private var matches: [ExerciseDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.exercises }
        return store.exercises.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || ($0.muscleGroup?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    /// Only offer to create when nothing already has that exact name.
    private var createName: String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let exists = store.exercises.contains {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        return exists ? nil : trimmed
    }

    var body: some View {
        NavigationStack {
            List {
                if let createName {
                    Section {
                        Button {
                            create(createName)
                        } label: {
                            HStack(spacing: Space.md) {
                                if isCreating {
                                    ProgressView().controlSize(.small).frame(width: 22)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color.accentPrimary)
                                        .frame(width: 22)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Add \"\(createName)\"")
                                        .foregroundStyle(Color.textPrimary)
                                    Text("New exercise")
                                        .font(.microJ)
                                        .foregroundStyle(Color.textTertiary)
                                }
                            }
                        }
                        .disabled(isCreating)
                    }
                }

                Section {
                    if matches.isEmpty, createName == nil {
                        Text("No exercises yet. Type a name to add one.")
                            .font(.subheadJ)
                            .foregroundStyle(Color.textTertiary)
                    }
                    ForEach(matches) { exercise in
                        Button {
                            onPick(exercise)
                            Haptics.play(.light)
                            dismiss()
                        } label: {
                            HStack(spacing: Space.md) {
                                IconTile(
                                    symbol: exercise.isBodyweight ? "figure.play" : "dumbbell.fill",
                                    color: ItemColor.fallback(for: exercise.id),
                                    size: TileSize.small,
                                )
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(exercise.name)
                                        .foregroundStyle(Color.textPrimary)
                                    if let subtitle = subtitle(exercise) {
                                        Text(subtitle)
                                            .font(.microJ)
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    if !matches.isEmpty {
                        Text("Your exercises")
                    }
                }
            }
            .searchable(text: $query, prompt: "Search or add an exercise")
            .navigationTitle("Exercises")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await store.loadExercises() }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private func subtitle(_ exercise: ExerciseDTO) -> String? {
        let parts = [exercise.muscleGroup, exercise.equipment].compactMap { $0 }
        return parts.isEmpty ? (exercise.isBodyweight ? "Bodyweight" : nil) : parts.joined(separator: " · ")
    }

    private func create(_ name: String) {
        isCreating = true
        Task {
            // Bodyweight is inferred from the name so the logger can hide the
            // weight field without asking a question during a workout.
            let created = await store.createExercise(
                name: name,
                muscleGroup: nil,
                isBodyweight: Self.looksBodyweight(name),
            )
            isCreating = false
            if let created {
                onPick(created)
                Haptics.play(.success)
                dismiss()
            }
        }
    }

    private static let bodyweightHints = [
        "pull-up", "pull up", "pullup", "chin-up", "chin up", "chinup",
        "push-up", "push up", "pushup", "dip", "plank", "sit-up", "sit up",
        "crunch", "burpee", "muscle-up", "muscle up", "hanging leg raise",
    ]

    static func looksBodyweight(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return bodyweightHints.contains { lowered.contains($0) }
    }
}
