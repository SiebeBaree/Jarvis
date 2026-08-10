import DesignSystem
import JarvisAPI
import SwiftUI

/// Route to an improvement area's detail screen.
private struct AreaRoute: Hashable, Identifiable {
    let areaId: String
    var id: String { areaId }
}

/// The Improve screen: your improvement areas with weekly photo check-ins
/// and J.A.R.V.I.S.'s commentary. Progress here is visual — photos over
/// weeks — and never feeds the daily score.
struct ImproveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = ImproveStore()
    @State private var showEditor = false
    @State private var showCheckinFlow = false
    @State private var areaRoute: AreaRoute?

    var body: some View {
        Group {
            if let response = store.response {
                content(response)
            } else if case .failed(let message) = store.areas {
                errorState(message)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add improvement area")
            }
        }
        .sheet(isPresented: $showEditor) {
            AreaEditorView(store: store)
        }
        .sheet(isPresented: $showCheckinFlow) {
            CheckinFlowView(store: store)
        }
        .navigationDestination(item: $areaRoute) { route in
            ImprovementAreaDetailView(store: store, areaId: route.areaId)
        }
        .task {
            store.configure(model)
            await store.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.load() }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ response: ImprovementAreaListResponse) -> some View {
        if response.areas.isEmpty {
            emptyState
        } else {
            List {
                Group {
                    if let error = store.mutationError {
                        errorBanner(error)
                    }
                    if response.anyDueThisWeek {
                        dueBanner
                    }
                    ForEach(response.areas) { area in
                        areaRow(area)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(
                    top: Space.xs, leading: PageMargin.standard,
                    bottom: Space.xs, trailing: PageMargin.standard,
                ))
                #if os(macOS)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                #endif
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await store.load(force: true) }
        }
    }

    private var dueBanner: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "camera")
                .font(.system(size: 15))
                .foregroundStyle(Color.accentPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly check-in due")
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Text("\(store.dueAreas.count) area\(store.dueAreas.count == 1 ? "" : "s") without a photo this week")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Space.sm)
            Button("Check in") { showCheckinFlow = true }
                .buttonStyle(.jarvisPrimary)
        }
        .padding(Space.lg)
        .background(Color.accentSubtle.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.accentPrimary.opacity(0.35), lineWidth: 0.5),
        )
    }

    private func areaRow(_ area: ImprovementAreaDTO) -> some View {
        HStack(spacing: Space.md) {
            Text(area.emoji ?? "🎯")
                .font(.system(size: 24))
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(area.name)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle(area))
                    .font(.subheadJ)
                    .foregroundStyle(area.dueThisWeek ? Color.accentPrimary : Color.textSecondary)
            }
            Spacer(minLength: Space.sm)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(minHeight: RowHeight.standard)
        .jarvisCard()
        .contentShape(Rectangle())
        .onTapGesture { areaRoute = AreaRoute(areaId: area.id) }
    }

    private func subtitle(_ area: ImprovementAreaDTO) -> String {
        if area.dueThisWeek { return "Check-in due this week" }
        if let thisWeek = area.thisWeek {
            return "Checked in \(HabitDisplay.shortLabel(for: thisWeek.dayKey))"
        }
        if let last = area.lastCheckinAt {
            return "Last check-in \(HabitDisplay.shortLabel(for: last))"
        }
        return "No check-ins yet"
    }

    // MARK: - Empty / error

    private var emptyState: some View {
        VStack(spacing: Space.lg) {
            Text("What do you want to improve?")
                .font(.title2J)
                .foregroundStyle(Color.textPrimary)
            Text("Posture, clothing, teeth, skin. Define an area and take one photo a week, so a month of small changes is something you can actually see.")
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Add your first area") { showEditor = true }
                .buttonStyle(.jarvisPrimary)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Button("Dismiss") {
                store.mutationError = nil
            }
            .buttonStyle(.plain)
            .font(.subheadJ)
            .foregroundStyle(Color.accentPrimary)
        }
        .padding(Space.md)
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
