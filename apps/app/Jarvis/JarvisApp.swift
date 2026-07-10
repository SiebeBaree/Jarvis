import SwiftUI

@main
struct JarvisApp: App {
    @State private var model = AppModel()
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil // follow system
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(colorScheme)
                .task { await model.bootstrap() }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif

        #if os(macOS)
        // ⌘, — the standard macOS Settings window (§B1).
        Settings {
            NavigationStack { SettingsView() }
                .environment(model)
                .preferredColorScheme(colorScheme)
                .frame(minWidth: 480, minHeight: 520)
        }
        #endif
    }
}
