import DesignSystem
import JarvisAPI
import SwiftUI

/// Route to a goal's detail screen.
private struct GoalRoute: Hashable, Identifiable {
    let goalId: String
    var id: String { goalId }
}

/// Route to a week's detail screen.
private struct WeekRoute: Hashable, Identifiable {
    let weekNumber: Int
    var id: Int { weekNumber }
}

/// Plan tab root = Block Overview (§B3): block header + 13-square week
/// strip, goal cards, and the This-Week card. Empty and upcoming states
/// route into onboarding / manual block creation.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = PlanStore()
    @State private var showOnboarding = false
    @State private var showManualBlock = false
    @State private var showVision = false
    @State private var showWeeklyReview = false
    @State private var showBlockRetro = false
    @State private var goalRoute: GoalRoute?
    @State private var weekRoute: WeekRoute?

    var body: some View {
        Group {
            if let response = store.content.value {
                content(response)
            } else if case .failed(let message) = store.content {
                errorState(message)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle("Plan")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Vision") { showVision = true }
                    .accessibilityLabel("Vision")
            }
        }
        .navigationDestination(isPresented: $showVision) {
            VisionView(store: store)
        }
        .navigationDestination(item: $goalRoute) { route in
            GoalDetailView(
                store: store,
                goalId: route.goalId,
                initialGoal: store.goal(id: route.goalId),
            )
        }
        .navigationDestination(item: $weekRoute) { route in
            WeekDetailView(store: store, weekNumber: route.weekNumber)
        }
        .setupWizardCover(isPresented: $showOnboarding)
        .reviewFlowCover(isPresented: $showWeeklyReview, kind: .weekly)
        .reviewFlowCover(isPresented: $showBlockRetro, kind: .block)
        .sheet(isPresented: $showManualBlock) {
            ManualBlockSheet(store: store)
        }
        .task {
            store.configure(model)
            await store.load()
        }
        .onChange(of: model.todayRevision) {
            Task { await store.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.load() }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ response: CurrentBlockResponse) -> some View {
        if let block = response.block {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if let error = store.mutationError {
                        errorBanner(error)
                    }
                    if response.isUpcoming {
                        upcomingHeader(block)
                    } else {
                        blockHeader(block, response: response)
                    }
                    goalsSection(response)
                    if !response.isUpcoming, response.isReviewWeek {
                        blockRetroCard
                    }
                    if !response.isUpcoming, let weekNumber = response.weekNumber {
                        thisWeekCard(block, weekNumber: weekNumber, response: response)
                    }
                }
                .padding(PageMargin.standard)
                #if os(macOS)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                #endif
            }
            .refreshable { await store.load() }
        } else {
            emptyState
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Space.lg) {
            Text(message)
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await store.load() }
            }
            .buttonStyle(.jarvisSecondary)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Space.sm) {
            Text(message)
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
            Spacer(minLength: Space.sm)
            Button("Retry") {
                store.mutationError = nil
                Task { await store.load() }
            }
            .buttonStyle(.plain)
            .font(.subheadJ)
            .foregroundStyle(Color.accentPrimary)
        }
        .padding(Space.md)
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: - Empty state (no block at all)

    private var emptyState: some View {
        VStack(spacing: Space.lg) {
            Text("No active block")
                .font(.title2J)
                .foregroundStyle(Color.textPrimary)
            Text("Set up your next 12 weeks — you write the areas, goals, and habits yourself.")
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Set up your plan") {
                showOnboarding = true
            }
            .buttonStyle(.jarvisPrimary)
            Button("Just create a block") {
                showManualBlock = true
            }
            .buttonStyle(.jarvisGhost)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Block header

    private func blockHeader(_ block: BlockDTO, response: CurrentBlockResponse) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(.title2J)
                        .foregroundStyle(Color.textPrimary)
                    Text("Block \(block.number) · \(PlanDisplay.rangeLabel(from: block.startDate, to: block.endDate))")
                        .font(.captionJ)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: Space.sm)
                if response.isReviewWeek {
                    Text("Review Week")
                        .font(.captionJ)
                        .foregroundStyle(Color.accentPrimary)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 3)
                        .background(Color.accentSubtle, in: Capsule())
                }
            }
            WeekStrip(
                currentWeek: response.weekNumber ?? 0,
                weekScores: response.weekScores,
                onTap: { weekRoute = WeekRoute(weekNumber: $0) },
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func upcomingHeader(_ block: BlockDTO) -> some View {
        let days = PlanDisplay.daysAway(block.startDate)
        return VStack(alignment: .leading, spacing: Space.xs) {
            Text(block.title)
                .font(.title2J)
                .foregroundStyle(Color.textPrimary)
            Text("Block \(block.number) · \(PlanDisplay.rangeLabel(from: block.startDate, to: block.endDate))")
                .font(.captionJ)
                .foregroundStyle(Color.textSecondary)
            Text("Starts \(HabitDisplay.shortLabel(for: block.startDate)) · \(days) \(days == 1 ? "day" : "days") away")
                .font(.headlineJ)
                .foregroundStyle(Color.accentPrimary)
                .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Goals

    @ViewBuilder
    private func goalsSection(_ response: CurrentBlockResponse) -> some View {
        let goals = response.goals.sorted { $0.sortOrder < $1.sortOrder }
        if !goals.isEmpty {
            SectionHeader("Goals")
                .padding(.top, Space.xs)
            ForEach(goals) { goal in
                goalCard(goal, weekNumber: response.weekNumber, tappable: !response.isUpcoming)
            }
        }
    }

    private func goalCard(_ goal: GoalWithProgressDTO, weekNumber: Int?, tappable: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(goal.title)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: Space.sm)
                if let trackStatus = goal.trackStatus {
                    TrackStatusPill(status: trackStatus)
                }
            }

            if let areaName = goal.areaName {
                TagChip([goal.areaEmoji, areaName].compactMap { $0 }.joined(separator: " "))
            }

            if let progress = goal.progress {
                HStack(spacing: Space.sm) {
                    PlanProgressBar(fraction: progress)
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.monoJ)
                        .foregroundStyle(Color.textSecondary)
                    if goal.manualProgress != nil {
                        Text("manual")
                            .font(.captionJ)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            if let weekNumber,
               let tactic = goal.tactics
                   .sorted(by: { $0.sortOrder < $1.sortOrder })
                   .first(where: { $0.fromWeek <= weekNumber && weekNumber <= $0.toWeek }) {
                Text("Week \(weekNumber): \(tactic.title)")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
        .contentShape(Rectangle())
        .onTapGesture {
            if tappable { goalRoute = GoalRoute(goalId: goal.id) }
        }
    }

    // MARK: - This week

    @ViewBuilder
    private func thisWeekCard(_ block: BlockDTO, weekNumber: Int, response: CurrentBlockResponse) -> some View {
        SectionHeader("This Week")
            .padding(.top, Space.xs)

        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(PlanDisplay.weekLabel(block: block, weekNumber: weekNumber))
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: Space.sm)
                weekScoreLine(weekNumber)
            }

            if response.isReviewWeek {
                Text("Review week — tasks are paused")
                    .font(.subheadJ)
                    .foregroundStyle(Color.accentPrimary)
            } else {
                let entries = store.tactics(forWeek: weekNumber)
                if entries.isEmpty {
                    Text("No tactics scheduled this week")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        ForEach(entries, id: \.tactic.id) { entry in
                            tacticChecklistRow(entry.tactic, goal: entry.goal, weekNumber: weekNumber)
                        }
                    }
                }
            }

            Button("Weekly review") { showWeeklyReview = true }
                .buttonStyle(.jarvisGhost)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    /// Review week (§B3): prominent retrospective launcher above This Week.
    private var blockRetroCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Block retrospective")
                .font(.headlineJ)
                .foregroundStyle(Color.accentPrimary)
            Text("Review week — close out this block")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
            Button("Start retrospective") { showBlockRetro = true }
                .buttonStyle(.jarvisPrimary)
                .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .background(Color.accentSubtle.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.accentPrimary.opacity(0.35), lineWidth: 0.5),
        )
    }

    /// "78 ▲6" — this week's avg vs the previous week (▲ success /
    /// ▼ warning, never red).
    @ViewBuilder
    private func weekScoreLine(_ weekNumber: Int) -> some View {
        let current = store.weekAvg(weekNumber)
        let previous = weekNumber > 1 ? store.weekAvg(weekNumber - 1) : nil
        HStack(spacing: Space.xs) {
            Text(current.map { "\(Int($0.rounded()))" } ?? "—")
                .font(.monoJ)
                .foregroundStyle(current == nil ? Color.textTertiary : Color.textPrimary)
            if let current, let previous {
                let delta = Int(current.rounded()) - Int(previous.rounded())
                if delta != 0 {
                    Text("\(delta > 0 ? "▲" : "▼")\(abs(delta))")
                        .font(.monoJ)
                        .foregroundStyle(delta > 0 ? Color.success : Color.warning)
                }
            }
        }
        .accessibilityLabel("Average score this week")
    }

    private func tacticChecklistRow(_ tactic: TacticDTO, goal: GoalWithProgressDTO, weekNumber: Int) -> some View {
        let done = store.completedWeeks(for: tactic).contains(weekNumber)
        return HStack(spacing: Space.md) {
            Button {
                Task { await store.setTacticWeek(tactic, weekNumber: weekNumber, done: !done) }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(done ? Color.success : Color.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(tactic.title)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(goal.title)
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Week strip

/// The 13-square strip: weeks 1–12 + "R". Past squares tinted by that
/// week's avg score band, current outlined accent, future hollow, R violet.
private struct WeekStrip: View {
    let currentWeek: Int
    let weekScores: [WeekScoreDTO]
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(1...13, id: \.self) { week in
                square(week)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func square(_ week: Int) -> some View {
        let tappable = week <= currentWeek
        let shape = RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)

        Button {
            onTap(week)
        } label: {
            Text(week == 13 ? "R" : "\(week)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(labelColor(week))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(fill(week), in: shape)
                .overlay(shape.strokeBorder(strokeColor(week), lineWidth: week == currentWeek ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
        .accessibilityLabel(week == 13 ? "Review week" : "Week \(week)")
    }

    private func avg(_ week: Int) -> Double? {
        weekScores.first { $0.weekNumber == week }?.avg
    }

    private func fill(_ week: Int) -> Color {
        if week == 13 { return .accentSubtle }
        if week < currentWeek {
            guard let avg = avg(week) else { return .bgSubtle }
            return PlanDisplay.bandColor(avg).opacity(0.25)
        }
        return .clear
    }

    private func labelColor(_ week: Int) -> Color {
        if week == 13 { return .accentPrimary }
        if week == currentWeek { return .accentPrimary }
        if week < currentWeek {
            guard let avg = avg(week) else { return .textTertiary }
            return PlanDisplay.bandColor(avg)
        }
        return .textTertiary
    }

    private func strokeColor(_ week: Int) -> Color {
        if week == currentWeek { return .accentPrimary }
        if week > currentWeek, week != 13 { return .borderHairline }
        return .clear
    }
}

// MARK: - Manual block sheet

/// Minimal manual block creation: title + fixed "next Monday" start.
private struct ManualBlockSheet: View {
    let store: PlanStore

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isSaving = false

    private let startDate = PlanDisplay.nextMonday()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Block title", text: $title)
                LabeledContent("Starts") {
                    Text("Monday, \(HabitDisplay.shortLabel(for: startDate))")
                        .foregroundStyle(Color.textSecondary)
                }
                LabeledContent("Ends") {
                    Text(HabitDisplay.shortLabel(for: DayKeyMath.addDays(startDate, 13 * 7 - 1)))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Block")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 260)
        #endif
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        Task {
            if await store.createBlock(title: trimmed, startDate: startDate) {
                dismiss()
            }
            isSaving = false
        }
    }
}
