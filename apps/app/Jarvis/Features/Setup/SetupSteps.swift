import DesignSystem
import JarvisAPI
import SwiftUI

// The individual wizard steps. Every list step is add/edit/remove and
// skippable — this is the user's plan, nothing is required except a block
// title and at least one goal.

// MARK: - Welcome

struct SetupWelcomeStep: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Circle()
                    .fill(Color.accentPrimary)
                    .frame(width: 36, height: 36)
                Text("You write the plan.\nJ.A.R.V.I.S. keeps track.")
                    .font(.title2J)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Space.md) {
                    welcomeLine("map", "Define your own areas, goals, and habits for the next 12 weeks — nothing is generated for you.")
                    welcomeLine("sparkles", "Add improvement areas (posture, clothing, teeth, …) with a weekly photo check-in and honest AI feedback.")
                    welcomeLine("brain", "J.A.R.V.I.S. learns who you are from your conversations. You can see and edit everything it knows.")
                }
            }
            .padding(PageMargin.standard)
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private func welcomeLine(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 24)
            Text(text)
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Life areas

struct SetupAreasStep: View {
    @Bindable var store: SetupWizardStore

    private static let suggestions: [(String, String)] = [
        ("Business", "💼"), ("Health", "💪"), ("Appearance", "🪞"), ("Social", "🗣️"), ("Mind", "🧠"),
    ]

    var body: some View {
        List {
            Section {
                ForEach($store.areas) { $area in
                    HStack(spacing: Space.md) {
                        TextField("🏷️", text: $area.emoji)
                            .frame(width: 44)
                        TextField("Area name", text: $area.name)
                    }
                }
                .onDelete { store.areas.remove(atOffsets: $0) }
                Button("+ Add area") {
                    store.areas.append(.init(name: "", emoji: ""))
                }
                .buttonStyle(.jarvisGhost)
            } header: {
                Text("The parts of your life you want to track — yours to define.")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .textCase(nil)
            }

            if !remainingSuggestions.isEmpty {
                Section("Suggestions") {
                    ForEach(remainingSuggestions, id: \.0) { name, emoji in
                        Button {
                            store.areas.append(.init(name: name, emoji: emoji))
                        } label: {
                            HStack {
                                Text("\(emoji) \(name)")
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Image(systemName: "plus")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var remainingSuggestions: [(String, String)] {
        Self.suggestions.filter { suggestion in
            !store.areas.contains { $0.name.caseInsensitiveCompare(suggestion.0) == .orderedSame }
        }
    }
}

// MARK: - Block

struct SetupBlockStep: View {
    @Bindable var store: SetupWizardStore

    var body: some View {
        Form {
            Section {
                TextField("Block title (e.g. \"Q3 — Ship it\")", text: $store.blockTitle)
                LabeledContent("Starts") {
                    Text("Monday, \(HabitDisplay.shortLabel(for: store.blockStartDate))")
                        .foregroundStyle(Color.textSecondary)
                }
                LabeledContent("Ends") {
                    Text(HabitDisplay.shortLabel(for: DayKeyMath.addDays(store.blockStartDate, 13 * 7 - 1)))
                        .foregroundStyle(Color.textSecondary)
                }
            } header: {
                Text("12 weeks of execution plus a review week. Scoring and weekly reviews run on this rhythm.")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .textCase(nil)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Goals

struct SetupGoalsStep: View {
    @Bindable var store: SetupWizardStore

    var body: some View {
        List {
            Section {
                ForEach($store.goals) { $goal in
                    VStack(alignment: .leading, spacing: Space.sm) {
                        TextField("Goal — concrete and yours", text: $goal.title)
                            .font(.headlineJ)
                        TextField("What done looks like (optional)", text: $goal.description, axis: .vertical)
                            .font(.subheadJ)
                            .lineLimit(1...3)
                        if !store.areas.isEmpty {
                            Picker("Area", selection: $goal.areaIndex) {
                                Text("No area").tag(Int?.none)
                                ForEach(Array(store.areas.enumerated()), id: \.offset) { index, area in
                                    Text(area.name.isEmpty ? "Area \(index + 1)" : area.name)
                                        .tag(Int?.some(index))
                                }
                            }
                            .font(.subheadJ)
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
                .onDelete { store.goals.remove(atOffsets: $0) }
                if store.goals.count < 6 {
                    Button("+ Add goal") {
                        store.goals.append(.init(title: ""))
                    }
                    .buttonStyle(.jarvisGhost)
                }
            } header: {
                Text("2–4 goals you will actually do this block. Only work that is genuinely yours — J.A.R.V.I.S. never writes these.")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .textCase(nil)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Habits

struct SetupHabitsStep: View {
    @Bindable var store: SetupWizardStore

    var body: some View {
        List {
            Section {
                ForEach($store.habits) { $habit in
                    HabitDraftRow(habit: $habit, goals: store.goals)
                }
                .onDelete { store.habits.remove(atOffsets: $0) }
                Button("+ Add habit") {
                    store.habits.append(.init(name: ""))
                }
                .buttonStyle(.jarvisGhost)
            } header: {
                Text("Habits score daily. Weekly habits judge the week, not the day — you can always swap days.")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .textCase(nil)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

/// One editable habit draft — extracted so the type checker stays fast.
private struct HabitDraftRow: View {
    @Binding var habit: SetupWizardStore.DraftHabit
    let goals: [SetupWizardStore.DraftGoal]

    private var stepperLabel: String {
        let unit: String = habit.type == .multiDaily ? "day" : "week"
        return "\(habit.targetReps)× per \(unit)"
    }

    private var stepperRange: ClosedRange<Int> {
        habit.type == .multiDaily ? 2...10 : 1...7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            TextField("Habit name", text: $habit.name)
                .font(.headlineJ)
            cadencePicker
            if habit.type != .daily {
                Stepper(stepperLabel, value: $habit.targetReps, in: stepperRange)
                    .font(.subheadJ)
            }
            if !goals.isEmpty {
                goalPicker
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var cadencePicker: some View {
        Picker("Cadence", selection: $habit.type) {
            Text("Daily").tag(HabitType.daily)
            Text("× per day").tag(HabitType.multiDaily)
            Text("× per week").tag(HabitType.weeklyFrequency)
        }
        .font(.subheadJ)
        .onChange(of: habit.type) { _, type in
            defaultReps(for: type)
        }
    }

    private func defaultReps(for type: HabitType) {
        switch type {
        case .daily: habit.targetReps = 1
        case .multiDaily: habit.targetReps = 2
        case .weeklyFrequency: habit.targetReps = 3
        }
    }

    private var goalPicker: some View {
        Picker("Supports goal", selection: $habit.goalIndex) {
            Text("No goal").tag(Optional<Int>.none)
            ForEach(Array(goals.enumerated()), id: \.offset) { index, goal in
                let label: String = goal.title.isEmpty ? "Goal \(index + 1)" : goal.title
                Text(label).tag(Optional<Int>.some(index))
            }
        }
        .font(.subheadJ)
    }
}

// MARK: - Improvement areas

struct SetupImproveStep: View {
    @Bindable var store: SetupWizardStore

    private static let suggestions: [(String, String)] = [
        ("Posture", "🧍"), ("Clothing", "👔"), ("Teeth", "😁"), ("Skin", "🧴"), ("Hair", "💇"),
    ]

    var body: some View {
        List {
            Section {
                ForEach($store.improvementAreas) { $area in
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack(spacing: Space.md) {
                            TextField("🏷️", text: $area.emoji)
                                .frame(width: 44)
                            TextField("Area (posture, clothing, …)", text: $area.name)
                                .font(.headlineJ)
                        }
                        TextField("What does better look like?", text: $area.betterLooksLike, axis: .vertical)
                            .font(.subheadJ)
                            .lineLimit(1...3)
                    }
                    .padding(.vertical, Space.xs)
                }
                .onDelete { store.improvementAreas.remove(atOffsets: $0) }
                Button("+ Add improvement area") {
                    store.improvementAreas.append(.init(name: "", emoji: ""))
                }
                .buttonStyle(.jarvisGhost)
            } header: {
                Text("Things about yourself you want to visibly improve. Once a week the app asks for a photo per area; J.A.R.V.I.S. compares it to previous weeks and tells you what changed.")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .textCase(nil)
            }

            if !remainingSuggestions.isEmpty {
                Section("Suggestions") {
                    ForEach(remainingSuggestions, id: \.0) { name, emoji in
                        Button {
                            store.improvementAreas.append(.init(name: name, emoji: emoji))
                        } label: {
                            HStack {
                                Text("\(emoji) \(name)")
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Image(systemName: "plus")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var remainingSuggestions: [(String, String)] {
        Self.suggestions.filter { suggestion in
            !store.improvementAreas.contains { $0.name.caseInsensitiveCompare(suggestion.0) == .orderedSame }
        }
    }
}

// MARK: - Seeding chat

/// Optional get-to-know-you conversation. The chat runs with kind "seeding":
/// J.A.R.V.I.S. only asks questions and saves memories — it plans nothing.
struct SetupSeedStep: View {
    @State private var chatStore = ChatStore()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Optional — skip anytime with Continue.")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
                Text("Tell J.A.R.V.I.S. who you are: your work and who does what, what you want to improve, how it should talk to you. It only remembers — it will not plan anything.")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.md)
            .background(Color.bgSubtle)

            ChatView(store: chatStore)
        }
        .onAppear { chatStore.newConversationKind = "seeding" }
    }
}

// MARK: - Done

struct SetupDoneStep: View {
    var body: some View {
        VStack(spacing: Space.xl) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.success)
            Text("Your plan is live")
                .font(.title2J)
                .foregroundStyle(Color.textPrimary)
            VStack(alignment: .leading, spacing: Space.sm) {
                doneLine("Today shows your tasks, habits, mood, and score.")
                doneLine("Improve (under Progress) holds your weekly photo check-ins.")
                doneLine("Settings → \"What J.A.R.V.I.S. knows\" shows everything it remembers — editable.")
            }
            .frame(maxWidth: 480, alignment: .leading)
        }
        .padding(PageMargin.standard)
    }

    private func doneLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Text("·")
                .font(.bodyJ)
                .foregroundStyle(Color.textTertiary)
            Text(text)
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
