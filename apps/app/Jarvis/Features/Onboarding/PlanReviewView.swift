import DesignSystem
import JarvisAPI
import SwiftUI

/// Plan Proposal Review (§B3): edits the interview result in place; nothing
/// is created server-side until Approve sends the ApplyPlanRequest.
struct PlanReviewView: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: OnboardingStore

    /// 0 = this Monday, 1 = next Monday.
    @State private var startChoice = 0
    @State private var editingVision = false
    @State private var visionExpanded = false

    var body: some View {
        if let result = Binding($store.result) {
            content(result)
        }
    }

    private func content(_ result: Binding<InterviewResultDTO>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                titleBlock
                visionCard(result)
                startChooser
                goalsSection(result)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.xl)
        }
        .safeAreaInset(edge: .bottom) {
            footer(result.wrappedValue)
        }
        .sheet(isPresented: $editingVision) {
            VisionEditSheet(text: result.visionDraft)
        }
        .alert(
            "Couldn't apply the plan",
            isPresented: Binding(
                get: { store.applyError != nil },
                set: { if !$0 { store.applyError = nil } },
            ),
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.applyError ?? "")
        }
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Your 12-week plan")
                .font(.title1J)
                .foregroundStyle(Color.textPrimary)
            Text("Review everything — edit or remove anything before you approve.")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Vision recap

    private func visionCard(_ result: Binding<InterviewResultDTO>) -> some View {
        let vision = result.wrappedValue.visionDraft
        return VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Vision") {
                Button("Edit") { editingVision = true }
                    .buttonStyle(.plain)
                    .font(.captionJ)
                    .foregroundStyle(Color.accentPrimary)
            }
            Text(vision)
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(visionExpanded ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
            if vision.count > 280 {
                Button(visionExpanded ? "Show less" : "Show more") {
                    withAnimation(.easeOut(duration: 0.25)) { visionExpanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(.subheadJ)
                .foregroundStyle(Color.accentPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Start chooser

    /// (next Monday, Monday after). If today is Monday, that's today and +7.
    private var mondayOptions: (this: DayKey, next: DayKey) {
        let today = DayKeyMath.todayKey(boundaryHour: model.settings?.dayBoundaryHour ?? 3)
        let weekday = Calendar.current.component(.weekday, from: DayKeyMath.date(from: today) ?? .now)
        let offsetToMonday = (9 - weekday) % 7 // weekday 2 = Monday
        let first = DayKeyMath.addDays(today, offsetToMonday)
        return (first, DayKeyMath.addDays(first, 7))
    }

    private var chosenStartDate: DayKey {
        let options = mondayOptions
        return startChoice == 0 ? options.this : options.next
    }

    private var startChooser: some View {
        let options = mondayOptions
        return VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Starts")
            HStack(spacing: Space.sm) {
                startChip(title: "This Monday", dayKey: options.this, choice: 0)
                startChip(title: "Next Monday", dayKey: options.next, choice: 1)
            }
        }
    }

    private func startChip(title: String, dayKey: DayKey, choice: Int) -> some View {
        let selected = startChoice == choice
        return Button {
            startChoice = choice
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Text(Self.shortDate(dayKey))
                    .font(.captionJ)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            selected ? Color.accentSubtle : Color.bgSurface,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous),
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(selected ? Color.accentPrimary : Color.borderHairline, lineWidth: selected ? 1 : 0.5)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static func shortDate(_ dayKey: DayKey) -> String {
        guard let date = DayKeyMath.date(from: dayKey) else { return dayKey }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Goals

    private func goalsSection(_ result: Binding<InterviewResultDTO>) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader("Goals")
            if result.wrappedValue.plan.goals.isEmpty {
                Text("No goals left. Keep at least one goal, or abandon the interview.")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .jarvisCard()
            }
            ForEach(Array(result.wrappedValue.plan.goals.enumerated()), id: \.offset) { index, snapshot in
                GoalCardView(
                    goal: goalBinding(result, index: index, snapshot: snapshot),
                    areas: result.wrappedValue.areas,
                    onRemove: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            var goals = result.wrappedValue.plan.goals
                            guard index < goals.count else { return }
                            goals.remove(at: index)
                            result.wrappedValue.plan.goals = goals
                        }
                    },
                )
            }
        }
    }

    /// Index binding hardened against removal races: reads fall back to the
    /// row's snapshot, writes to a stale index are dropped.
    private func goalBinding(
        _ result: Binding<InterviewResultDTO>,
        index: Int,
        snapshot: PlanGoalDTO,
    ) -> Binding<PlanGoalDTO> {
        Binding(
            get: {
                let goals = result.wrappedValue.plan.goals
                return index < goals.count ? goals[index] : snapshot
            },
            set: { newValue in
                guard index < result.wrappedValue.plan.goals.count else { return }
                result.wrappedValue.plan.goals[index] = newValue
            },
        )
    }

    // MARK: - Footer

    private func footer(_ result: InterviewResultDTO) -> some View {
        let goals = result.plan.goals
        let habitCount = goals.reduce(0) { $0 + $1.habits.count }
        let taskCount = goals.reduce(0) { $0 + $1.tasks.count }
        let isApplying = store.phase == .applying
        let canApprove = !goals.isEmpty && !isApplying

        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderHairline)
                .frame(height: 0.5)
            VStack(spacing: Space.sm) {
                Button {
                    Task { await store.apply(startDate: chosenStartDate) }
                } label: {
                    Group {
                        if isApplying {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Text("Approve plan")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.jarvisPrimary)
                .disabled(!canApprove)
                .opacity(canApprove || isApplying ? 1 : 0.5)

                Text(
                    goals.isEmpty
                        ? "Keep at least one goal, or abandon the interview."
                        : "Creates \(Self.count(goals.count, "goal")), \(Self.count(habitCount, "habit")), \(Self.count(taskCount, "task"))"
                )
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.md)
        }
        .frame(maxWidth: .infinity)
        .background(Color.bgSurface)
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
