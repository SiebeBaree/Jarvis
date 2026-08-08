import DesignSystem
import JarvisAPI
import SwiftUI

/// Settings sheet content. Today's gear presents it wrapped in a
/// NavigationStack, so the area editor can push from inside the sheet.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var confirmingSignOut = false
    @State private var isSigningOut = false
    @State private var confirmingReset = false
    @State private var isResetting = false
    @State private var resetError: String?

    var body: some View {
        Form {
            accountSection
            appearanceSection
            scoringSection
            planSection
            dangerSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog(
            "Sign out of Jarvis?",
            isPresented: $confirmingSignOut,
            titleVisibility: .visible,
        ) {
            Button("Sign out", role: .destructive) {
                isSigningOut = true
                Task { await model.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("Account") {
            HStack {
                Text("Email")
                Spacer()
                Text(email)
                    .foregroundStyle(Color.textSecondary)
            }
            Button(role: .destructive) {
                confirmingSignOut = true
            } label: {
                if isSigningOut {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Sign out")
                        .foregroundStyle(Color.danger)
                }
            }
            .disabled(isSigningOut)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearanceMode) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
        }
    }

    private var scoringSection: some View {
        Section {
            HStack {
                Text("Weights")
                Spacer()
                Text(weightsLabel)
                    .font(.monoJ)
                    .foregroundStyle(Color.textSecondary)
            }
            HStack {
                Text("Day boundary")
                Spacer()
                Text(dayBoundaryLabel)
                    .foregroundStyle(Color.textSecondary)
            }
            HStack {
                Text("Week starts")
                Spacer()
                Text(weekStartLabel)
                    .foregroundStyle(Color.textSecondary)
            }
        } header: {
            Text("Scoring")
        } footer: {
            Text("Managed on the server")
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var planSection: some View {
        Section("Organize") {
            NavigationLink("Areas") { AreasEditorView() }
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingReset = true
            } label: {
                if isResetting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Reset all data…")
                        .foregroundStyle(Color.danger)
                }
            }
            .disabled(isResetting)
            .confirmationDialog(
                "Erase everything and start over?",
                isPresented: $confirmingReset,
                titleVisibility: .visible,
            ) {
                Button("Erase all data", role: .destructive) { resetAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes your habits, tasks, goals, mood and score history, body metrics and photos. Your account and settings stay. This cannot be undone.")
            }
            if let resetError {
                Text(resetError)
                    .font(.subheadJ)
                    .foregroundStyle(Color.danger)
            }
        } header: {
            Text("Danger zone")
        } footer: {
            Text("You land back on an empty Today and start over.")
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func resetAccount() {
        isResetting = true
        resetError = nil
        Task {
            do {
                _ = try await model.api.resetAccount()
                model.invalidateToday()
                dismiss()
            } catch {
                model.handle(error)
                resetError = TodayStore.message(for: error)
            }
            isResetting = false
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .font(.monoJ)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - Derived labels

    private var email: String {
        if case .loggedIn(let user, _) = model.session { return user.email }
        return "—"
    }

    private var weightsLabel: String {
        guard let weights = model.settings?.scoreWeights else { return "40 / 40 / 20" }
        return "\(Int(weights.tasks)) / \(Int(weights.habits)) / \(Int(weights.feel))"
    }

    private var dayBoundaryLabel: String {
        let hour = model.settings?.dayBoundaryHour ?? 3
        let display = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(display):00 \(suffix)"
    }

    private var weekStartLabel: String {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let start = model.settings?.weekStartsOn ?? 1
        guard (1...7).contains(start) else { return "Monday" }
        return names[start - 1]
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }
}
