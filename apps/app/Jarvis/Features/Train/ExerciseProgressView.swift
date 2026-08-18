import Charts
import DesignSystem
import JarvisAPI
import SwiftUI

/// One movement over time: is the top set going up?
///
/// The line is estimated 1RM rather than raw weight, because a weight-only
/// chart says you got weaker the week you did 3 × 12 instead of 5 × 5. The
/// actual set behind each point is listed underneath, so the estimate never
/// has to be taken on trust.
struct ExerciseProgressView: View {
    @Environment(AppModel.self) private var model

    let exerciseId: String
    let name: String
    let store: WorkoutsStore

    @State private var state: LoadState<[ExerciseHistoryPointDTO]> = .idle

    var body: some View {
        Group {
            switch state {
            case .loaded(let points) where points.isEmpty:
                EmptyState(
                    symbol: "chart.line.uptrend.xyaxis",
                    title: "No history yet",
                    message: "Log a few sets of \(name) and the trend shows up here.",
                    tint: ItemColor.rose.color,
                )
            case .loaded(let points):
                content(points)
            case .failed(let message):
                VStack(spacing: Space.lg) {
                    Text(message)
                        .font(.bodyJ)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.jarvisSecondary)
                }
                .padding(Space.xxl)
            default:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle(name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private func load() async {
        guard let api = model.api as APIClient? else { return }
        if state.value == nil { state = .loading }
        do {
            let response = try await api.exerciseHistory(id: exerciseId, limit: 40)
            state = .loaded(response.points)
        } catch {
            model.handle(error)
            state = .failed(TodayStore.message(for: error))
        }
    }

    @ViewBuilder
    private func content(_ points: [ExerciseHistoryPointDTO]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                summary(points)
                chart(points)
                history(points)
            }
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.md)
            #if os(macOS)
            .frame(maxWidth: PageMargin.contentMaxWidth)
            .frame(maxWidth: .infinity)
            #endif
        }
    }

    // MARK: - Summary

    private func summary(_ points: [ExerciseHistoryPointDTO]) -> some View {
        let best = points.compactMap(\.estimatedOneRepMax).max()
        let heaviest = points.compactMap(\.topWeightKg).max()
        let change = trend(points)

        return HStack(spacing: Space.lg) {
            stat(heaviest.map { "\(Format.weight($0)) kg" } ?? Placeholder.noValue, "heaviest set")
            stat(best.map { "\(Format.weight($0)) kg" } ?? Placeholder.noValue, "best est. 1RM")
            if let change {
                stat(change.text, "last 30 days", tint: change.tint)
            }
            Spacer(minLength: 0)
        }
        .jarvisCard(padding: Space.md)
    }

    /// Change in estimated 1RM against the oldest session in the last month.
    private func trend(_ points: [ExerciseHistoryPointDTO]) -> (text: String, tint: Color)? {
        let today = DayKeyMath.todayKey(boundaryHour: model.settings?.dayBoundaryHour ?? 3)
        let cutoff = DayKeyMath.addDays(today, -30)
        let window = points.filter { $0.dayKey >= cutoff }
        guard let first = window.first?.estimatedOneRepMax,
              let last = window.last?.estimatedOneRepMax,
              window.count >= 2, first > 0
        else { return nil }

        let delta = last - first
        if abs(delta) < 0.05 { return ("no change", Color.textSecondary) }
        return (
            "\(delta > 0 ? "+" : "")\(Format.weight(delta)) kg",
            delta > 0 ? Color.success : Color.warning
        )
    }

    private func stat(_ value: String, _ label: String, tint: Color = .textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.numeralJ)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.microJ)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private func chart(_ points: [ExerciseHistoryPointDTO]) -> some View {
        let plotted = points.filter { $0.estimatedOneRepMax != nil }
        if plotted.count >= 2 {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader("Estimated 1RM", subtitle: "from the best set of each workout")
                Chart(plotted) { point in
                    LineMark(
                        x: .value("Date", DayKeyMath.date(from: point.dayKey) ?? .now),
                        y: .value("Est. 1RM", point.estimatedOneRepMax ?? 0),
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(ItemColor.rose.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))

                    PointMark(
                        x: .value("Date", DayKeyMath.date(from: point.dayKey) ?? .now),
                        y: .value("Est. 1RM", point.estimatedOneRepMax ?? 0),
                    )
                    .foregroundStyle(ItemColor.rose.color)
                    .symbolSize(28)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.borderHairline)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(Format.weight(number))
                                    .font(.microJ)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.microJ)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisCard()
        }
    }

    // MARK: - History

    private func history(_ points: [ExerciseHistoryPointDTO]) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Every session", subtitle: "\(points.count)")

            VStack(spacing: 0) {
                ForEach(Array(points.reversed().enumerated()), id: \.element.id) { index, point in
                    HStack(spacing: Space.md) {
                        Text(HabitDisplay.shortLabel(for: point.dayKey))
                            .font(.microJ)
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 52, alignment: .leading)

                        Text(topSetLabel(point))
                            .font(.headlineJ)
                            .foregroundStyle(Color.textPrimary)

                        Spacer(minLength: Space.sm)

                        Text("\(point.setCount) sets · \(Format.weight(point.volumeKg)) kg")
                            .font(.microJ)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.vertical, Space.sm)

                    if index < points.count - 1 {
                        Divider().overlay(Color.borderHairline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func topSetLabel(_ point: ExerciseHistoryPointDTO) -> String {
        guard let reps = point.topReps else { return Placeholder.noValue }
        guard let weight = point.topWeightKg, weight > 0 else { return "\(reps) reps" }
        return "\(Format.weight(weight)) × \(reps)"
    }
}
