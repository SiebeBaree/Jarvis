import DesignSystem
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.session {
        case .checking:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgCanvas)
        case .loggedOut:
            LoginView()
        case .loggedIn:
            MainShell()
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case today
    case tasks
    case habits
    case goals
    case trends
    case metrics
    case improve

    var id: String { rawValue }

    /// iPhone tab bar (Trends/Metrics/Improve live behind Today's toolbar there).
    static let tabSections: [AppSection] = [.today, .tasks, .habits, .goals]

    /// macOS sidebar shows everything, grouped.
    static let sidebarGroups: [(title: String?, sections: [AppSection])] = [
        (nil, [.today]),
        ("Aim", [.goals]),
        ("Track", [.tasks, .habits]),
        ("Progress", [.trends, .improve, .metrics]),
    ]

    var title: String {
        switch self {
        case .today: "Today"
        case .tasks: "Tasks"
        case .habits: "Habits"
        case .goals: "Goals"
        case .trends: "Trends"
        case .metrics: "Metrics"
        case .improve: "Improve"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .tasks: "checklist"
        case .habits: "repeat"
        case .goals: "target"
        case .trends: "chart.line.uptrend.xyaxis"
        case .metrics: "scalemass"
        case .improve: "figure.stand"
        }
    }
}

struct MainShell: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppSection = .today

    var body: some View {
        shell
            .overlay(alignment: .bottom) { SyncStatusBar() }
            .onChange(of: model.requestedSection) { _, section in
                if let section {
                    selection = section
                    model.requestedSection = nil
                }
            }
    }

    @ViewBuilder
    private var shell: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Array(AppSection.sidebarGroups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group.sections) { section in
                            Label(section.title, systemImage: section.icon)
                                .tag(section)
                        }
                    } header: {
                        if let title = group.title {
                            Text(title)
                                .font(.captionJ)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                settingsFooter
            }
        } detail: {
            NavigationStack {
                detailView(for: selection)
            }
            .frame(minWidth: 640)
        }
        .background(Color.bgCanvas)
        .background(sectionShortcuts)
        #else
        TabView(selection: $selection) {
            ForEach(AppSection.tabSections) { section in
                NavigationStack {
                    detailView(for: section)
                }
                .tabItem { Label(section.title, systemImage: section.icon) }
                .tag(section)
            }
        }
        #endif
    }

    #if os(macOS)
    private var settingsFooter: some View {
        SidebarSettingsRow()
            .padding(.horizontal, Space.sm)
            .padding(.bottom, Space.sm)
    }

    /// ⌘1–⌘4 jump to the main sections.
    private var sectionShortcuts: some View {
        Group {
            shortcutButton(.today, "1")
            shortcutButton(.tasks, "2")
            shortcutButton(.habits, "3")
            shortcutButton(.goals, "4")
        }
        .hidden()
    }

    private func shortcutButton(_ section: AppSection, _ key: KeyEquivalent) -> some View {
        Button(section.title) { selection = section }
            .keyboardShortcut(key, modifiers: .command)
    }
    #endif

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .today: TodayView()
        case .tasks: TasksView()
        case .habits: HabitsView()
        case .goals: GoalsView()
        case .trends: TrendsView()
        case .metrics:
            MetricsView()
                .background(Color.bgCanvas)
                .navigationTitle("Metrics")
        case .improve: ImproveView()
        }
    }
}

#if os(macOS)
/// Settings pinned to the sidebar bottom (§B1); ⌘, comes from the Settings scene.
private struct SidebarSettingsRow: View {
    @State private var showSettings = false

    var body: some View {
        Button {
            showSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
                .frame(minWidth: 480, minHeight: 520)
        }
    }
}
#endif
