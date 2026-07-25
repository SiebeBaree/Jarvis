import Charts
import DesignSystem
import JarvisAPI
import Observation
import SwiftUI

// MARK: - Store

@Observable
@MainActor
final class MetricsStore {
    private(set) var types: LoadState<[MetricTypeDTO]> = .idle
    /// 90-day entry window per metric type id, ascending by dayKey.
    private(set) var entries: [String: [MetricEntryDTO]] = [:]
    var mutationError: String?

    private var model: AppModel?

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    /// Codable so it survives on disk and paints on a cold launch.
    private struct Snapshot: Codable {
        var types: [MetricTypeDTO]
        var entries: [String: [MetricEntryDTO]]
    }

    func load(force: Bool = false) async {
        guard let model else { return }
        if !force, let cached = model.store.read(Snapshot.self, .metrics) {
            types = .loaded(cached.value.types)
            entries = cached.value.entries
            if cached.isFresh { return }
        }
        if types.value == nil { types = .loading }
        do {
            let today = DayKeyMath.todayKey()
            async let typesResponse = model.api.metricTypes()
            async let entriesResponse = model.api.metricEntries(
                from: DayKeyMath.addDays(today, -89),
                to: today,
            )
            let (typeList, entryList) = try await (typesResponse, entriesResponse)
            let visibleTypes = typeList.metricTypes
                .filter { $0.archivedAt == nil }
                .sorted { $0.sortOrder < $1.sortOrder }
            let grouped = Dictionary(grouping: entryList.entries, by: \.metricTypeId)
                .mapValues { $0.sorted { $0.dayKey < $1.dayKey } }
            types = .loaded(visibleTypes)
            entries = grouped
            model.store.write(Snapshot(types: visibleTypes, entries: grouped), .metrics)
        } catch {
            model.handle(error)
            if types.value == nil {
                types = .failed(TodayStore.message(for: error))
            } else {
                mutationError = TodayStore.message(for: error)
            }
        }
    }

    func log(type: MetricTypeDTO, dayKey: DayKey, value: Double) async {
        await run { try await $0.putMetric(typeId: type.id, dayKey: dayKey, value: value) }
    }

    func create(_ request: MetricTypeCreateRequest) async {
        await run { try await $0.createMetricType(request) }
    }

    func patch(id: String, _ patch: JSONObject) async {
        await run { try await $0.patchMetricType(id: id, patch) }
    }

    func archive(id: String) async {
        await run { try await $0.patchMetricType(id: id, ["archived": .bool(true)]) }
    }

    func deleteEntry(type: MetricTypeDTO, dayKey: DayKey) async {
        await run { try await $0.deleteMetric(typeId: type.id, dayKey: dayKey) }
    }

    private func run<T: Sendable>(_ operation: (APIClient) async throws -> T) async {
        guard let model else { return }
        do {
            _ = try await operation(model.api)
            mutationError = nil
            model.invalidateToday()
            await load(force: true)
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
        }
    }

    // MARK: - Derived

    /// Latest entry, and the reference entry ~30 days back for the delta.
    func latest(for type: MetricTypeDTO) -> MetricEntryDTO? {
        entries[type.id]?.last
    }

    func delta30(for type: MetricTypeDTO) -> Double? {
        guard let list = entries[type.id], let latest = list.last else { return nil }
        let cutoff = DayKeyMath.addDays(DayKeyMath.todayKey(), -30)
        let baseline = list.last { $0.dayKey <= cutoff } ?? list.first
        guard let baseline, baseline.id != latest.id else { return nil }
        return latest.value - baseline.value
    }
}

// MARK: - Formatting helpers

enum MetricFormat {
    static func value(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(max(min(decimals, 3), 0))f", value)
    }

    static func signedDelta(_ delta: Double, type: MetricTypeDTO) -> String {
        let magnitude = value(abs(delta), decimals: type.decimals)
        let sign = delta < 0 ? "−" : "+"
        return "\(sign)\(magnitude) \(type.unit)"
    }

    /// Green when moving toward the goal direction, amber when away,
    /// neutral gray when the metric has no direction.
    static func deltaColor(_ delta: Double, type: MetricTypeDTO) -> Color {
        switch type.goalDirection {
        case "down": delta < 0 ? .success : (delta > 0 ? .warning : .textSecondary)
        case "up": delta > 0 ? .success : (delta < 0 ? .warning : .textSecondary)
        default: .textSecondary
        }
    }

    static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}

// MARK: - Metrics list

struct MetricsView: View {
    @Environment(AppModel.self) private var model

    @State private var store = MetricsStore()
    @State private var logTarget: MetricTypeDTO?
    @State private var editTarget: MetricTypeDTO?
    @State private var showNewMetric = false

    var body: some View {
        Group {
            switch store.types {
            case .loaded(let types):
                if types.isEmpty {
                    emptyState
                } else {
                    list(types)
                }
            case .failed(let message):
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(PageMargin.standard)
            default:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewMetric = true
                } label: {
                    Label("New metric", systemImage: "plus")
                }
                .accessibilityLabel("New metric")
            }
        }
        .sheet(item: $logTarget) { type in
            MetricLogSheet(type: type) { dayKey, value in
                await store.log(type: type, dayKey: dayKey, value: value)
            }
        }
        .sheet(isPresented: $showNewMetric) {
            MetricEditorSheet(existing: nil) { request, _ in
                await store.create(request)
            }
        }
        .sheet(item: $editTarget) { type in
            MetricEditorSheet(existing: type) { _, patch in
                if let patch {
                    await store.patch(id: type.id, patch)
                }
            }
        }
        .task {
            store.configure(model)
            await store.load()
        }
    }

    private func list(_ types: [MetricTypeDTO]) -> some View {
        ScrollView {
            VStack(spacing: Space.md) {
                if let error = store.mutationError {
                    Text(error)
                        .font(.subheadJ)
                        .foregroundStyle(Color.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(types) { type in
                    NavigationLink {
                        MetricDetailView(type: type, store: store)
                    } label: {
                        MetricCard(
                            type: type,
                            entries: store.entries[type.id] ?? [],
                            delta: store.delta30(for: type),
                            onLog: { logTarget = type },
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit") { editTarget = type }
                        Button("Archive", role: .destructive) {
                            Task { await store.archive(id: type.id) }
                        }
                    }
                }
            }
            .padding(PageMargin.standard)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.load(force: true) }
    }

    private var emptyState: some View {
        VStack(spacing: Space.md) {
            Text("Track anything — weight, body fat, whatever matters")
                .font(.headlineJ)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            Text("Each metric gets a chart, deltas, and an optional goal.")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
            Button("New metric") { showNewMetric = true }
                .buttonStyle(.jarvisPrimary)
                .padding(.top, Space.xs)
        }
        .padding(PageMargin.standard)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Metric card

private struct MetricCard: View {
    let type: MetricTypeDTO
    let entries: [MetricEntryDTO]
    let delta: Double?
    let onLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.name)
                        .font(.headlineJ)
                        .foregroundStyle(Color.textPrimary)
                    if let latest = entries.last {
                        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                            Text("\(MetricFormat.value(latest.value, decimals: type.decimals)) \(type.unit)")
                                .font(.title2J)
                                .monospacedDigit()
                                .foregroundStyle(Color.textPrimary)
                            Text(HabitDisplay.shortLabel(for: latest.dayKey))
                                .font(.captionJ)
                                .foregroundStyle(Color.textTertiary)
                        }
                    } else {
                        Text("No entries yet")
                            .font(.subheadJ)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                Spacer(minLength: Space.sm)
                Button("+ Log", action: onLog)
                    .buttonStyle(.jarvisSecondary)
            }

            if entries.count >= 2 {
                sparkline
            }

            if let delta {
                Text("\(MetricFormat.signedDelta(delta, type: type)) · 30d")
                    .font(.monoJ)
                    .foregroundStyle(MetricFormat.deltaColor(delta, type: type))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private var sparkline: some View {
        Chart(entries) { entry in
            if let date = DayKeyMath.date(from: entry.dayKey) {
                LineMark(
                    x: .value("Day", date),
                    y: .value(type.name, entry.value),
                )
                .foregroundStyle(Color.accentPrimary)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 36)
    }
}

// MARK: - Log sheet

private struct MetricLogSheet: View {
    let type: MetricTypeDTO
    let onSave: (DayKey, Double) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var valueText = ""
    @State private var date: Date = .now
    @State private var isSaving = false
    @FocusState private var valueFocused: Bool

    private var parsed: Double? { MetricFormat.parse(valueText) }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("Value", text: $valueText)
                        #if os(iOS)
                        .keyboardType(type.decimals > 0 ? .decimalPad : .numberPad)
                        #endif
                        .font(.bodyJ)
                        .focused($valueFocused)
                    Text(type.unit)
                        .font(.subheadJ)
                        .foregroundStyle(Color.textSecondary)
                }
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
            }
            .formStyle(.grouped)
            .navigationTitle("Log \(type.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let value = parsed else { return }
                        isSaving = true
                        let dayKey = DayKeyMath.dayFormatter.string(from: date)
                        Task {
                            await onSave(dayKey, value)
                            dismiss()
                        }
                    }
                    .disabled(parsed == nil || isSaving)
                }
            }
            .onAppear { valueFocused = true }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 240)
        #endif
        .presentationDetents([.medium])
    }
}

// MARK: - New / edit metric sheet

private struct MetricEditorSheet: View {
    /// nil = create; non-nil = edit (saves via PATCH).
    let existing: MetricTypeDTO?
    let onSave: (MetricTypeCreateRequest, JSONObject?) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unit = ""
    @State private var decimals = 1
    @State private var hasGoal = false
    @State private var goalText = ""
    @State private var goalDirection = "down"
    @State private var isSaving = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !unit.trimmingCharacters(in: .whitespaces).isEmpty
            && (!hasGoal || MetricFormat.parse(goalText) != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Weight)", text: $name)
                    TextField("Unit (e.g. kg)", text: $unit)
                    Stepper("Decimals: \(decimals)", value: $decimals, in: 0...3)
                }
                Section {
                    Toggle("Goal", isOn: $hasGoal)
                    if hasGoal {
                        HStack {
                            TextField("Target value", text: $goalText)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text(unit)
                                .font(.subheadJ)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Picker("Direction", selection: $goalDirection) {
                            Text("Down").tag("down")
                            Text("Up").tag("up")
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "New metric" : "Edit metric")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave || isSaving)
                }
            }
            .onAppear(perform: prefill)
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 360)
        #endif
        .presentationDetents([.medium, .large])
    }

    private func prefill() {
        guard let existing else { return }
        name = existing.name
        unit = existing.unit
        decimals = existing.decimals
        if let goal = existing.goalValue {
            hasGoal = true
            goalText = MetricFormat.value(goal, decimals: existing.decimals)
        }
        goalDirection = existing.goalDirection ?? "down"
    }

    private func save() {
        isSaving = true
        let goal = hasGoal ? MetricFormat.parse(goalText) : nil
        let request = MetricTypeCreateRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            unit: unit.trimmingCharacters(in: .whitespaces),
            decimals: decimals,
            goalValue: goal,
            goalDirection: hasGoal ? goalDirection : nil,
        )
        // PATCH payload sends explicit nulls so a removed goal clears server-side.
        let patch: JSONObject = [
            "name": .string(request.name),
            "unit": .string(request.unit),
            "decimals": .int(decimals),
            "goalValue": goal.map { JSONValue.double($0) } ?? .null,
            "goalDirection": hasGoal ? .string(goalDirection) : .null,
        ]
        Task {
            await onSave(request, existing == nil ? nil : patch)
            dismiss()
        }
    }
}

// MARK: - Metric detail (full chart + history)

private struct MetricDetailView: View {
    let type: MetricTypeDTO
    let store: MetricsStore

    private enum DetailRange: Int, CaseIterable, Identifiable {
        case month = 30
        case quarter = 90
        case year = 365

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .month: "30d"
            case .quarter: "90d"
            case .year: "1y"
            }
        }
    }

    @Environment(AppModel.self) private var model

    @State private var range: DetailRange = .quarter
    @State private var entries: LoadState<[MetricEntryDTO]> = .idle
    @State private var showLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Picker("Range", selection: $range) {
                    ForEach(DetailRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                chartCard
                historyCard
            }
            .padding(PageMargin.standard)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color.bgCanvas)
        .navigationTitle(type.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("+ Log") { showLog = true }
            }
        }
        .sheet(isPresented: $showLog) {
            MetricLogSheet(type: type) { dayKey, value in
                await store.log(type: type, dayKey: dayKey, value: value)
                await load()
            }
        }
        .task { await load() }
        .onChange(of: range) {
            Task { await load() }
        }
    }

    private func load() async {
        if entries.value == nil { entries = .loading }
        do {
            let today = DayKeyMath.todayKey()
            let response = try await model.api.metricEntries(
                typeId: type.id,
                from: DayKeyMath.addDays(today, -(range.rawValue - 1)),
                to: today,
            )
            entries = .loaded(response.entries.sorted { $0.dayKey < $1.dayKey })
        } catch {
            model.handle(error)
            entries = .failed(TodayStore.message(for: error))
        }
    }

    @ViewBuilder
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(type.name)

            switch entries {
            case .loaded(let list):
                if list.isEmpty {
                    Text("No entries in this range")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    chart(list)
                }
            case .failed(let message):
                Text(message)
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
            default:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func chart(_ list: [MetricEntryDTO]) -> some View {
        Chart {
            ForEach(list) { entry in
                if let date = DayKeyMath.date(from: entry.dayKey) {
                    LineMark(
                        x: .value("Day", date),
                        y: .value(type.name, entry.value),
                    )
                    .foregroundStyle(Color.accentPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(
                        x: .value("Day", date),
                        y: .value(type.name, entry.value),
                    )
                    .foregroundStyle(Color.accentPrimary)
                    .symbolSize(18)
                }
            }
            if let goal = type.goalValue {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Color.success)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal \(MetricFormat.value(goal, decimals: type.decimals))")
                            .font(.captionJ)
                            .foregroundStyle(Color.success)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks {
                AxisGridLine().foregroundStyle(Color.borderHairline)
                AxisValueLabel().font(.captionJ).foregroundStyle(Color.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks {
                AxisValueLabel().font(.captionJ).foregroundStyle(Color.textTertiary)
            }
        }
        .frame(height: 220)
    }

    @ViewBuilder
    private var historyCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Entries")

            if let list = entries.value {
                if list.isEmpty {
                    Text("Nothing logged yet")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    ForEach(list.reversed()) { entry in
                        HStack {
                            Text(HabitDisplay.shortLabel(for: entry.dayKey))
                                .font(.subheadJ)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text("\(MetricFormat.value(entry.value, decimals: type.decimals)) \(type.unit)")
                                .font(.monoJ)
                                .foregroundStyle(Color.textPrimary)
                            Button {
                                Task {
                                    await store.deleteEntry(type: type, dayKey: entry.dayKey)
                                    await load()
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete entry")
                        }
                        .frame(minHeight: 28)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }
}
