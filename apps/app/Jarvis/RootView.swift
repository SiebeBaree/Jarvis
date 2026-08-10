import DesignSystem
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.session {
        case .checking:
            LaunchPlaceholder()
        case .loggedOut:
            LoginView()
        case .loggedIn:
            MainShell()
        }
    }
}

/// Shown for the instant between launch and knowing whether there is a
/// session. A bare spinner on a blank canvas made every cold start read as a
/// stall, so this is the app's own mark holding its place instead.
private struct LaunchPlaceholder: View {
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            Color.bgCanvas.ignoresSafeArea()
            Circle()
                .stroke(AngularGradient.scoreArc, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 54, height: 54)
                .scaleEffect(isBreathing ? 1 : 0.88)
                .opacity(isBreathing ? 1 : 0.55)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: isBreathing
                )
        }
        .onAppear { isBreathing = true }
        .accessibilityLabel("Loading")
    }
}

// MARK: - Sections
//
// Four, down from seven. Goals, Trends, Body metrics and the improvement-area
// check-ins used to be either a sidebar row nobody visited or an unlabelled
// icon in Today's toolbar; they are all answers to "how am I doing over time",
// so they are now one Progress surface. Today · Tasks · Habits · Progress maps
// to: the day, what I have to do, what I do every day, how it is going.

enum AppSection: String, CaseIterable, Identifiable {
    case today
    case tasks
    case habits
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Overview"
        case .tasks: "Tasks"
        case .habits: "Habits"
        case .progress: "Progress"
        }
    }

    /// Distinct silhouettes beat a consistent fill weight here: four filled
    /// circles are four identical blobs at tab-bar size, and the point of a
    /// tab icon is to be recognisable before it is read.
    var icon: String {
        switch self {
        case .today: "sun.max.fill"
        case .tasks: "checklist"
        case .habits: "repeat"
        case .progress: "chart.bar.fill"
        }
    }

    var tint: Color {
        switch self {
        case .today: ItemColor.amber.color
        case .tasks: ItemColor.blue.color
        case .habits: ItemColor.violet.color
        case .progress: ItemColor.green.color
        }
    }
}

struct MainShell: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppSection = .today
    @State private var showSettings = false

    var body: some View {
        shell
            .overlay(alignment: .bottom) { SyncStatusBar() }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
                    #if os(macOS)
                    .frame(minWidth: 520, minHeight: 560)
                    #endif
            }
            .environment(\.openSettings, OpenSettingsAction { showSettings = true })
            .onChange(of: model.requestedSection) { _, section in
                if let section {
                    withJarvisAnimation(Motion.quick) { selection = section }
                    model.requestedSection = nil
                }
            }
            .task { Haptics.prepare() }
    }

    @ViewBuilder
    private var shell: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                SidebarSettingsRow { showSettings = true }
                    .padding(.horizontal, Space.sm)
                    .padding(.bottom, Space.sm)
            }
        } detail: {
            NavigationStack {
                detailView(for: selection)
            }
            .frame(minWidth: 620)
        }
        .background(Color.bgCanvas)
        .background(sectionShortcuts)
        #else
        TabView(selection: $selection) {
            ForEach(AppSection.allCases) { section in
                Tab(section.title, systemImage: section.icon, value: section) {
                    NavigationStack {
                        detailView(for: section)
                    }
                }
            }
        }
        .tint(Color.accentPrimary)
        #endif
    }

    #if os(macOS)
    /// ⌘1–⌘4 jump to the sections.
    private var sectionShortcuts: some View {
        Group {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { selection = section }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(index + 1)")),
                        modifiers: .command
                    )
            }
        }
        .hidden()
    }
    #endif

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .today: TodayView()
        case .tasks: TasksView()
        case .habits: HabitsView()
        case .progress: ProgressHubView()
        }
    }
}

// MARK: - Settings access
//
// Settings is a sheet owned by the shell rather than a screen each tab has to
// re-present, so any view can raise it without knowing where it lives.

struct OpenSettingsAction {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func callAsFunction() { handler() }
}

private struct OpenSettingsKey: EnvironmentKey {
    static let defaultValue = OpenSettingsAction {}
}

extension EnvironmentValues {
    var openSettings: OpenSettingsAction {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
}

#if os(macOS)
/// Settings pinned to the sidebar bottom; ⌘, comes from the Settings scene.
private struct SidebarSettingsRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Settings", systemImage: "gearshape.fill")
                .font(.subheadStrongJ)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
