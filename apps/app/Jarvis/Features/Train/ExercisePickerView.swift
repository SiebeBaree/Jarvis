import DesignSystem
import JarvisAPI
import SwiftUI

/// Pick an exercise, or create one by typing its name.
///
/// Creating is deliberately the same gesture as searching: the first time you
/// do an exercise you type it, and every time after that the same typing finds
/// it. That is also why the server treats a duplicate name as a reuse, so one
/// movement keeps one history.
///
/// The search box is a plain field rather than `.searchable()`. On macOS that
/// modifier collapses into a small fixed-width toolbar field that truncates
/// even its own placeholder, which is unusable for names like "Supine barbell
/// bench press".
struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let store: WorkoutsStore
    let onPick: (ExerciseDTO) -> Void

    @State private var query = ""
    @State private var isCreating = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matches: [ExerciseDTO] {
        guard !trimmedQuery.isEmpty else { return store.exercises }
        return store.exercises.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedQuery)
                || ($0.muscleGroup?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }

    /// Only offer to create when nothing already has that exact name.
    private var createName: String? {
        guard !trimmedQuery.isEmpty else { return nil }
        let exists = store.exercises.contains {
            $0.name.caseInsensitiveCompare(trimmedQuery) == .orderedSame
        }
        return exists ? nil : trimmedQuery
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                InlineSearchField(
                    prompt: "Search or add an exercise",
                    text: $query,
                    onSubmit: {
                        if let createName { create(createName) }
                    },
                )
                .padding(.horizontal, PageMargin.standard)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.md)

                list
            }
            .background(Color.bgCanvas)
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
        .frame(minWidth: 560, idealWidth: 600, minHeight: 520, idealHeight: 600)
        #endif
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Space.xs) {
                if let createName {
                    createRow(createName)
                }

                if matches.isEmpty, createName == nil {
                    Text(
                        store.exercises.isEmpty
                            ? "No exercises yet. Type a name to add one."
                            : "Nothing matches that. Keep typing to add it as a new exercise.",
                    )
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.xl)
                }

                ForEach(matches) { exercise in
                    exerciseRow(exercise)
                }
            }
            .padding(.horizontal, PageMargin.standard)
            .padding(.bottom, Space.xl)
        }
    }

    private func createRow(_ name: String) -> some View {
        HStack(spacing: Space.md) {
            if isCreating {
                ProgressView().controlSize(.small).frame(width: TileSize.small)
            } else {
                IconTile(symbol: "plus", color: .indigo, size: TileSize.small)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Add \"\(name)\"")
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("New exercise")
                    .font(.microJ)
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: RowHeight.standard)
        .jarvisRow()
        .contentShape(Rectangle())
        .pressable { if !isCreating { create(name) } }
    }

    private func exerciseRow(_ exercise: ExerciseDTO) -> some View {
        HStack(spacing: Space.md) {
            IconTile(
                symbol: exercise.isBodyweight ? "figure.play" : "dumbbell.fill",
                color: ItemColor.fallback(for: exercise.id),
                size: TileSize.small,
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.name)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                    // Long names wrap instead of being clipped: an exercise you
                    // cannot read the end of is one you cannot pick with
                    // confidence.
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let subtitle = subtitle(exercise) {
                    Text(subtitle)
                        .font(.microJ)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: RowHeight.standard)
        .jarvisRow()
        .contentShape(Rectangle())
        .pressable {
            onPick(exercise)
            dismiss()
        }
    }

    private func subtitle(_ exercise: ExerciseDTO) -> String? {
        let parts = [exercise.muscleGroup, exercise.equipment].compactMap { $0 }
        if parts.isEmpty { return exercise.isBodyweight ? "Bodyweight" : nil }
        return parts.joined(separator: " · ")
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
