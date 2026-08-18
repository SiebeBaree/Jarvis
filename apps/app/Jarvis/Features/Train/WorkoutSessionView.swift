import DesignSystem
import JarvisAPI
import SwiftUI

/// The workout itself. One card per exercise, and each card answers the two
/// questions you actually have standing at the rack:
///
///   what am I meant to do   → the routine's target, at the top
///   what did I do last time → the previous session's sets, right under it
///
/// The logging control is pre-filled from last time (or the target), so the
/// common case — matching or beating what you did before — is a single tap,
/// and the +/- buttons are sized for a thumb rather than a cursor.
struct WorkoutSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let sessionId: String
    let store: WorkoutsStore

    @State private var showExercisePicker = false
    @State private var showFinishConfirm = false
    @State private var editingSet: EditingSet?
    @State private var progressRoute: ExerciseRoute?

    private struct EditingSet: Identifiable {
        let workoutSet: WorkoutSetDTO
        let exerciseName: String
        var id: String { workoutSet.id }
    }

    private struct ExerciseRoute: Hashable, Identifiable {
        let exerciseId: String
        let name: String
        var id: String { exerciseId }
    }

    private var session: SessionDetailDTO? { store.detail(sessionId) }

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle(session?.title ?? "Workout")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add exercise", systemImage: "plus") { showExercisePicker = true }
                    if let session, session.isFinished {
                        Button("Reopen workout", systemImage: "arrow.uturn.backward") {
                            store.reopenWorkout(sessionId)
                        }
                    }
                    Divider()
                    Button("Delete workout", systemImage: "trash", role: .destructive) {
                        store.deleteWorkout(sessionId)
                        dismiss()
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerView(store: store) { exercise in
                store.addExercise(exercise, to: sessionId)
            }
        }
        .sheet(item: $editingSet) { editing in
            SetEditorView(
                workoutSet: editing.workoutSet,
                exerciseName: editing.exerciseName,
                onSave: { weight, reps, isWarmup in
                    store.updateSet(
                        sessionId: sessionId,
                        set: editing.workoutSet,
                        weightKg: weight,
                        reps: reps,
                        isWarmup: isWarmup,
                    )
                },
                onDelete: {
                    store.deleteSet(sessionId: sessionId, set: editing.workoutSet)
                },
            )
        }
        .navigationDestination(item: $progressRoute) { route in
            ExerciseProgressView(exerciseId: route.exerciseId, name: route.name, store: store)
        }
        .task {
            store.bind(model)
            await store.loadDetail(sessionId)
        }
    }

    // MARK: - Content

    private func content(_ session: SessionDetailDTO) -> some View {
        ScrollView {
            LazyVStack(spacing: Space.md) {
                summaryCard(session)

                ForEach(session.exercises) { exercise in
                    ExerciseCard(
                        exercise: exercise,
                        isFinished: session.isFinished,
                        onLog: { weight, reps, isWarmup in
                            store.logSet(
                                sessionId: sessionId,
                                exerciseId: exercise.exerciseId,
                                weightKg: weight,
                                reps: reps,
                                isWarmup: isWarmup,
                            )
                        },
                        onEditSet: { loggedSet in
                            editingSet = EditingSet(workoutSet: loggedSet, exerciseName: exercise.name)
                        },
                        onShowProgress: {
                            progressRoute = ExerciseRoute(
                                exerciseId: exercise.exerciseId,
                                name: exercise.name,
                            )
                        },
                    )
                }

                Button {
                    showExercisePicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.jarvisSecondary)

                if !session.isFinished {
                    Button("Finish workout") { showFinishConfirm = true }
                        .buttonStyle(.jarvisProminent)
                        .padding(.top, Space.sm)
                }
            }
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.md)
            #if os(macOS)
            .frame(maxWidth: PageMargin.contentMaxWidth)
            .frame(maxWidth: .infinity)
            #endif
        }
        .confirmationDialog(
            "Finish this workout?",
            isPresented: $showFinishConfirm,
            titleVisibility: .visible,
        ) {
            Button("Finish") {
                store.finishWorkout(sessionId)
                Haptics.play(.success)
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text(finishMessage(session))
        }
    }

    /// Names what is still unfinished rather than just asking "are you sure" —
    /// forgetting the last exercise is the mistake worth catching.
    private func finishMessage(_ session: SessionDetailDTO) -> String {
        let remaining = session.exercises.filter { !$0.isComplete }
        guard !remaining.isEmpty else {
            return "Everything in the plan is done. Nice."
        }
        let names = remaining.prefix(3).map(\.name).joined(separator: ", ")
        let extra = remaining.count > 3 ? " and \(remaining.count - 3) more" : ""
        return "Still to do: \(names)\(extra)."
    }

    private func summaryCard(_ session: SessionDetailDTO) -> some View {
        HStack(spacing: Space.lg) {
            stat("\(session.setCount)", "sets")
            divider
            stat(Format.weight(session.volumeKg), "kg lifted")
            divider
            stat("\(session.exercises.filter(\.isComplete).count)/\(session.exercises.count)", "done")
            Spacer(minLength: 0)
            if session.isFinished {
                TagChip("Finished", symbol: "checkmark", tint: Color.success)
            }
        }
        .jarvisCard(padding: Space.md)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.numeralJ)
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.microJ)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.borderHairline)
            .frame(width: 1, height: 26)
    }
}

// MARK: - Exercise card

private struct ExerciseCard: View {
    let exercise: SessionExerciseDTO
    let isFinished: Bool
    let onLog: (Double?, Int?, Bool) -> Void
    let onEditSet: (WorkoutSetDTO) -> Void
    let onShowProgress: () -> Void

    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var isWarmup = false
    @State private var didPrefill = false

    private var color: ItemColor { ItemColor.fallback(for: exercise.exerciseId) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header
            lastTimeLine
            if !exercise.sets.isEmpty { loggedSets }
            if !isFinished { logControl }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
        .onAppear { prefill() }
        // Re-prefill from the set just logged, so a straight-sets run needs no
        // typing at all after the first set.
        .onChange(of: exercise.sets.count) { _, _ in prefill(force: true) }
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.name)
                    .font(.title3J)
                    .foregroundStyle(Color.textPrimary)
                if let target = exercise.target {
                    Text(targetLine(target))
                        .font(.subheadStrongJ)
                        .foregroundStyle(color.color)
                } else if let muscle = exercise.muscleGroup {
                    Text(muscle)
                        .font(.subheadJ)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Spacer(minLength: Space.sm)

            if exercise.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.success)
                    .transition(.scale.combined(with: .opacity))
            }
            Button(action: onShowProgress) {
                Image(systemName: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.jarvisIcon())
            .accessibilityLabel("Progress for \(exercise.name)")
        }
        .jarvisAnimation(Motion.pop, value: exercise.isComplete)
    }

    private func targetLine(_ target: SessionTargetDTO) -> String {
        var text = "\(exercise.workingSets.count)/\(target.sets) sets"
        if let reps = target.repsLabel { text += " × \(reps)" }
        if let weight = target.weightKg, weight > 0 { text += " @ \(Format.weight(weight)) kg" }
        return text
    }

    /// The whole reason this screen exists.
    @ViewBuilder
    private var lastTimeLine: some View {
        if let previous = exercise.previous, !previous.workingSets.isEmpty {
            HStack(alignment: .top, spacing: Space.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.sets(previous.workingSets))
                        .font(.monoJ)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Last time · \(HabitDisplay.shortLabel(for: previous.dayKey))")
                        .font(.microJ)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        } else {
            Text("First time doing this one.")
                .font(.subheadJ)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var loggedSets: some View {
        VStack(spacing: Space.xs) {
            ForEach(exercise.sets) { set in
                HStack(spacing: Space.md) {
                    Text(set.isWarmup ? "W" : "\(workingIndex(of: set))")
                        .font(.microJ)
                        .foregroundStyle(set.isWarmup ? Color.textTertiary : color.color)
                        .frame(width: 20, height: 20)
                        .background(
                            set.isWarmup ? Color.bgSubtle : color.soft,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous),
                        )

                    Text(Format.set(set))
                        .font(.headlineJ)
                        .foregroundStyle(set.isWarmup ? Color.textSecondary : Color.textPrimary)

                    if let comparison = comparison(for: set) {
                        TagChip(comparison.label, symbol: comparison.symbol, tint: comparison.color)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .pressable(scale: 0.99) { onEditSet(set) }
            }
        }
    }

    private func workingIndex(of set: WorkoutSetDTO) -> Int {
        (exercise.workingSets.firstIndex { $0.id == set.id } ?? 0) + 1
    }

    /// How this set compares with the same set number last time — the little
    /// "+2.5" that makes progressive overload visible without any charts.
    private func comparison(for set: WorkoutSetDTO) -> (label: String, symbol: String, color: Color)? {
        guard !set.isWarmup,
              let previous = exercise.previous?.workingSets,
              let index = exercise.workingSets.firstIndex(where: { $0.id == set.id }),
              index < previous.count,
              let now = set.weightKg,
              let before = previous[index].weightKg,
              now > 0, before > 0
        else { return nil }

        let delta = now - before
        if abs(delta) < 0.01 {
            // Same weight — more reps still counts as progress.
            guard let nowReps = set.reps, let beforeReps = previous[index].reps, nowReps > beforeReps
            else { return nil }
            return ("+\(nowReps - beforeReps) reps", "arrow.up", Color.success)
        }
        let sign = delta > 0 ? "+" : ""
        return (
            "\(sign)\(Format.weight(delta)) kg",
            delta > 0 ? "arrow.up" : "arrow.down",
            delta > 0 ? Color.success : Color.warning
        )
    }

    // MARK: - Logging

    private var logControl: some View {
        VStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                if !exercise.isBodyweight {
                    NumberStepper(
                        value: $weight,
                        step: 2.5,
                        range: 0...600,
                        unit: "kg",
                        format: Format.weight,
                    )
                }
                NumberStepper(
                    value: Binding(
                        get: { Double(reps) },
                        set: { reps = Int($0) },
                    ),
                    step: 1,
                    range: 0...100,
                    unit: "reps",
                    format: { String(Int($0)) },
                )
            }

            HStack(spacing: Space.sm) {
                Button {
                    isWarmup.toggle()
                    Haptics.play(.light)
                } label: {
                    Label("Warm-up", systemImage: isWarmup ? "checkmark.circle.fill" : "circle")
                        .font(.microJ)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isWarmup ? color.color : Color.textTertiary)

                Spacer(minLength: 0)

                Button {
                    onLog(exercise.isBodyweight ? nil : weight, reps, isWarmup)
                    Haptics.play(.success)
                } label: {
                    Text("Log set").frame(minWidth: 92)
                }
                .buttonStyle(.jarvisPrimary)
                .disabled(reps == 0 && (exercise.isBodyweight || weight == 0))
            }
        }
    }

    /// Fills the control with the most useful guess: what you just lifted, or
    /// what you lifted last time at this set number, or the routine's target.
    private func prefill(force: Bool = false) {
        guard force || !didPrefill else { return }
        didPrefill = true

        if let last = exercise.sets.last(where: { !$0.isWarmup }) {
            weight = last.weightKg ?? 0
            reps = last.reps ?? 0
            isWarmup = false
            return
        }
        let nextIndex = exercise.workingSets.count
        if let previous = exercise.previous?.workingSets, nextIndex < previous.count {
            weight = previous[nextIndex].weightKg ?? 0
            reps = previous[nextIndex].reps ?? 0
            return
        }
        if let previous = exercise.previous?.workingSets.first {
            weight = previous.weightKg ?? 0
            reps = previous.reps ?? 0
            return
        }
        weight = exercise.target?.weightKg ?? 0
        reps = exercise.target?.repsLow ?? 0
    }
}

// MARK: - Number stepper

/// A big-target numeric control: minus, value, plus. Built rather than using
/// `Stepper` because at the gym this needs a 44 pt hit area and a value you
/// can read from arm's length, and because tapping the number opens a keypad
/// for the jump that stepping would take twenty taps to reach.
struct NumberStepper: View {
    @Binding var value: Double
    let step: Double
    let range: ClosedRange<Double>
    let unit: String
    let format: (Double) -> String

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus") {
                value = max(range.lowerBound, value - step)
            }

            Group {
                if isEditing {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.numeralJ)
                        .focused($fieldFocused)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .onSubmit(commit)
                        .onChange(of: fieldFocused) { _, focused in
                            if !focused { commit() }
                        }
                } else {
                    VStack(spacing: -2) {
                        Text(format(value))
                            .font(.numeralJ)
                            .foregroundStyle(Color.textPrimary)
                        Text(unit)
                            .font(.microJ)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draft = format(value)
                        isEditing = true
                        fieldFocused = true
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: RowHeight.tapTarget)

            stepButton("plus") {
                value = min(range.upperBound, value + step)
            }
        }
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    private func commit() {
        let cleaned = draft.replacingOccurrences(of: ",", with: ".")
        if let parsed = Double(cleaned) {
            value = min(range.upperBound, max(range.lowerBound, parsed))
        }
        isEditing = false
        fieldFocused = false
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.play(.light)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: RowHeight.tapTarget, height: RowHeight.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Increase \(unit)" : "Decrease \(unit)")
    }
}

// MARK: - Set editor

/// Correcting a set after the fact.
private struct SetEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let workoutSet: WorkoutSetDTO
    let exerciseName: String
    let onSave: (Double?, Int?, Bool) -> Void
    let onDelete: () -> Void

    @State private var weight = ""
    @State private var reps = ""
    @State private var isWarmup = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text(exerciseName)
                    .font(.title3J)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .bottom, spacing: Space.lg) {
                    CaptionedField(
                        caption: "Weight",
                        prompt: "0",
                        text: $weight,
                        width: 80,
                        suffix: "kg",
                    )
                    CaptionedField(caption: "Reps", prompt: "0", text: $reps, width: 64)
                    Spacer(minLength: 0)
                }

                Toggle("Warm-up set", isOn: $isWarmup)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textPrimary)

                Text("Warm-up sets are kept but left out of your volume and personal bests.")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Delete set", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .buttonStyle(.jarvisSecondary)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .padding(PageMargin.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgCanvas)
            .navigationTitle("Set \(workoutSet.setIndex)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            Double(weight.replacingOccurrences(of: ",", with: ".")),
                            Int(reps),
                            isWarmup,
                        )
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            weight = workoutSet.weightKg.map(Format.weight) ?? ""
            reps = workoutSet.reps.map(String.init) ?? ""
            isWarmup = workoutSet.isWarmup
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 380)
        #endif
    }
}
