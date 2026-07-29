import DesignSystem
import JarvisAPI
import SwiftUI

/// What the editor produced. Create and patch differ enough on the wire that
/// the caller decides which to send, but the form fills in both from the same
/// fields so they can never drift apart.
struct GoalDraft {
    var title: String
    var description: String?
    var horizon: GoalHorizon
    var startDate: DayKey
    var targetDate: DayKey
    var unit: String?
    var startValue: Double?
    var targetValue: Double?

    var create: GoalCreateRequest {
        GoalCreateRequest(
            title: title,
            description: description,
            horizon: horizon,
            startDate: startDate,
            targetDate: targetDate,
            unit: unit,
            startValue: startValue,
            targetValue: targetValue,
        )
    }

    var patch: JSONObject {
        [
            "title": .string(title),
            "description": description.map { JSONValue.string($0) } ?? .null,
            "horizon": .string(horizon.rawValue),
            "startDate": .string(startDate),
            "targetDate": .string(targetDate),
            "unit": unit.map { JSONValue.string($0) } ?? .null,
            "startValue": startValue.map { JSONValue.double($0) } ?? .null,
            "targetValue": targetValue.map { JSONValue.double($0) } ?? .null,
        ]
    }

    func apply(to goal: inout GoalDTO) {
        goal.title = title
        goal.description = description
        goal.horizon = horizon
        goal.startDate = startDate
        goal.targetDate = targetDate
        goal.unit = unit
        goal.startValue = startValue
        goal.targetValue = targetValue
        // Clearing the numeric target clears the reading with it, so the goal
        // falls back to milestones cleanly instead of keeping a stale number.
        if targetValue == nil { goal.currentValue = nil }
    }
}

struct GoalEditorView: View {
    let goal: GoalDTO?
    let onSave: (GoalDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var horizon: GoalHorizon = .short
    @State private var startDate = Date.now
    @State private var targetDate = Date.now.addingTimeInterval(90 * 86_400)
    @State private var isMeasurable = false
    @State private var unit = ""
    @State private var startValue = ""
    @State private var targetValue = ""

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A measurable goal needs both ends of the range, and they must differ —
    /// otherwise there is no percentage to compute. Mirrors the server's rule.
    private var numbersAreValid: Bool {
        guard isMeasurable else { return true }
        guard let start = Double(startValue.replacingOccurrences(of: ",", with: ".")),
              let target = Double(targetValue.replacingOccurrences(of: ",", with: "."))
        else { return false }
        return start != target
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && targetDate >= startDate && numbersAreValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What are you aiming at?", text: $title)
                    TextField("Why it matters (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Picker("Horizon", selection: $horizon) {
                        ForEach(GoalHorizon.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker(
                        "Target",
                        selection: $targetDate,
                        in: startDate...,
                        displayedComponents: .date,
                    )
                } footer: {
                    Text("The time bar runs from the start date to the target date.")
                }

                Section {
                    Toggle("Track a number", isOn: $isMeasurable.animation())
                    if isMeasurable {
                        TextField("Unit (kg, €, books…)", text: $unit)
                        HStack {
                            Text("From")
                            Spacer()
                            numberField($startValue)
                        }
                        HStack {
                            Text("To")
                            Spacer()
                            numberField($targetValue)
                        }
                    }
                } footer: {
                    Text(
                        isMeasurable
                            ? "Progress is measured from \"From\" to \"To\", so goals that go down (92 → 80 kg) work the same as goals that go up."
                            : "Without a number, progress comes from the milestones you tick off inside the goal.",
                    )
                }
            }
            .formStyle(.grouped)
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: populate)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    private func numberField(_ text: Binding<String>) -> some View {
        TextField("0", text: text)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 140)
            .font(.monoJ)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }

    private func populate() {
        guard let goal else { return }
        title = goal.title
        notes = goal.description ?? ""
        horizon = goal.horizon
        startDate = DayKeyMath.date(from: goal.startDate) ?? .now
        targetDate = DayKeyMath.date(from: goal.targetDate) ?? .now
        isMeasurable = goal.targetValue != nil
        unit = goal.unit ?? ""
        startValue = goal.startValue.map { GoalValueFormat.string($0) } ?? ""
        targetValue = goal.targetValue.map { GoalValueFormat.string($0) } ?? ""
    }

    private func save() {
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            GoalDraft(
                title: trimmedTitle,
                description: trimmedNotes.isEmpty ? nil : trimmedNotes,
                horizon: horizon,
                startDate: DayKeyMath.dayFormatter.string(from: startDate),
                targetDate: DayKeyMath.dayFormatter.string(from: targetDate),
                unit: isMeasurable && !trimmedUnit.isEmpty ? trimmedUnit : nil,
                startValue: isMeasurable ? number(startValue) : nil,
                targetValue: isMeasurable ? number(targetValue) : nil,
            ),
        )
        dismiss()
    }

    /// Accepts a comma as the decimal separator — the keyboard gives one on a
    /// Belgian locale.
    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}
