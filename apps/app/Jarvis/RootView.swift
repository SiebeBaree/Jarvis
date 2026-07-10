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

/// App sections. Chat (S3) is added later without reshuffling these.
enum AppSection: String, CaseIterable, Identifiable {
    case today
    case tasks
    case habits
    case plan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .tasks: "Tasks"
        case .habits: "Habits"
        case .plan: "Plan"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .tasks: "checklist"
        case .habits: "repeat"
        case .plan: "map"
        }
    }
}

struct MainShell: View {
    @State private var selection: AppSection = .today

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(AppSection.allCases) { section in
                        Label(section.title, systemImage: section.icon)
                            .tag(section)
                    }
                } header: {
                    Text("Jarvis")
                        .font(.captionJ)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            NavigationStack {
                detailView(for: selection)
            }
            .frame(minWidth: 640)
        }
        .background(Color.bgCanvas)
        #else
        TabView(selection: $selection) {
            ForEach(AppSection.allCases) { section in
                NavigationStack {
                    detailView(for: section)
                }
                .tabItem { Label(section.title, systemImage: section.icon) }
                .tag(section)
            }
        }
        #endif
    }

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .today: TodayView()
        case .tasks: TasksView()
        case .habits: HabitsView()
        case .plan: PlanView()
        }
    }
}
