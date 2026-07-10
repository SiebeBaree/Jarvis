import DesignSystem
import JarvisAPI
import SwiftUI

/// Minimal Stage-1 goals editor so tasks and habits can link to goals.
struct GoalsEditorView: View {
    @Environment(AppModel.self) private var model

    @State private var state: LoadState<[GoalDTO]> = .idle
    @State private var areas: [AreaDTO] = []
    @State private var showingAdd = false
    @State private var editing: GoalDTO?
    @State private var pendingDelete: GoalDTO?
    @State private var actionError: String?

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: Space.md) {
                    Text(message)
                        .font(.subheadJ)
                        .foregroundStyle(Color.danger)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await fetch() }
                    }
                    .buttonStyle(.jarvisSecondary)
                }
                .padding(PageMargin.standard)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .loaded(let goals):
                let visible = goals.filter { $0.status != "dropped" }
                if visible.isEmpty {
                    VStack(spacing: Space.md) {
                        Text("No goals yet")
                            .font(.bodyJ)
                            .foregroundStyle(Color.textSecondary)
                        Text(Self.caption)
                            .font(.subheadJ)
                            .foregroundStyle(Color.textTertiary)
                            .multilineTextAlignment(.center)
                        Button("Add goal") { showingAdd = true }
                            .buttonStyle(.jarvisGhost)
                    }
                    .padding(PageMargin.standard)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    goalList(visible)
                }
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add goal", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            GoalFormSheet(goal: nil, areas: areas) { title, description, areaId in
                _ = try await model.api.createGoal(
                    GoalCreateRequest(title: title, description: description, areaId: areaId),
                )
                model.invalidateToday()
                await fetch()
            }
        }
        .sheet(item: $editing) { goal in
            GoalFormSheet(goal: goal, areas: areas) { title, description, areaId in
                _ = try await model.api.patchGoal(
                    id: goal.id,
                    [
                        "title": .string(title),
                        "description": description.map { .string($0) } ?? .null,
                        "areaId": areaId.map { .string($0) } ?? .null,
                    ],
                )
                model.invalidateToday()
                await fetch()
            }
        }
        .confirmationDialog(
            "Delete goal",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } },
            ),
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) {
                if let goal = pendingDelete {
                    Task { await delete(goal) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Tasks and habits linked to this goal keep working — they just lose the link.")
        }
        .task {
            await fetch()
            if let response = try? await model.api.areas() {
                areas = response.areas.filter { $0.archivedAt == nil }
            }
        }
    }

    private static let caption =
        "Goals get their full home in the Plan tab later — this is the minimal editor "
            + "so tasks and habits can link to them."

    private func goalList(_ goals: [GoalDTO]) -> some View {
        let active = goals.filter { $0.status == "active" }
        let achieved = goals.filter { $0.status == "achieved" }
        return List {
            Section {
                if let actionError {
                    Text(actionError)
                        .font(.subheadJ)
                        .foregroundStyle(Color.danger)
                        .listRowBackground(Color.bgCanvas)
                        .listRowSeparator(.hidden)
                }
                Text(Self.caption)
                    .font(.subheadJ)
                    .foregroundStyle(Color.textTertiary)
                    .listRowBackground(Color.bgCanvas)
                    .listRowSeparator(.hidden)
            }

            if !active.isEmpty {
                Section {
                    ForEach(active) { goal in
                        row(for: goal)
                    }
                } header: {
                    captionHeader("Active")
                }
            }

            if !achieved.isEmpty {
                Section {
                    ForEach(achieved) { goal in
                        row(for: goal)
                    }
                } header: {
                    captionHeader("Done")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await fetch() }
    }

    private func row(for goal: GoalDTO) -> some View {
        let isAchieved = goal.status == "achieved"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Space.sm) {
                Text(goal.title)
                    .font(.headlineJ)
                    .foregroundStyle(isAchieved ? Color.textTertiary : Color.textPrimary)
                    .strikethrough(isAchieved, color: .textTertiary)
                    .lineLimit(2)
                if let areaName = areas.first(where: { $0.id == goal.areaId })?.name {
                    TagChip(areaName)
                }
            }
            if let description = goal.description, !description.isEmpty {
                Text(description)
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = goal }
        .frame(minHeight: RowHeight.standard)
        .listRowBackground(Color.bgCanvas)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = goal
            } label: {
                Label("Delete", systemImage: "trash")
            }
            if !isAchieved {
                Button {
                    Task { await markAchieved(goal) }
                } label: {
                    Label("Mark achieved", systemImage: "checkmark.seal")
                }
                .tint(.success)
            }
        }
        .contextMenu {
            Button("Edit") { editing = goal }
            if !isAchieved {
                Button("Mark achieved") {
                    Task { await markAchieved(goal) }
                }
            }
            Button("Delete", role: .destructive) { pendingDelete = goal }
        }
    }

    private func captionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.captionJ)
            .tracking(0.6)
            .foregroundStyle(Color.textSecondary)
    }

    // MARK: - Data

    private func fetch() async {
        if state.value == nil { state = .loading }
        do {
            let response = try await model.api.goals()
            state = .loaded(response.goals)
        } catch {
            model.handle(error)
            state = .failed(error.localizedDescription)
        }
    }

    private func markAchieved(_ goal: GoalDTO) async {
        do {
            _ = try await model.api.patchGoal(id: goal.id, ["status": .string("achieved")])
            actionError = nil
            model.invalidateToday()
            await fetch()
        } catch {
            model.handle(error)
            actionError = error.localizedDescription
        }
    }

    private func delete(_ goal: GoalDTO) async {
        do {
            _ = try await model.api.deleteGoal(id: goal.id)
            actionError = nil
            pendingDelete = nil
            model.invalidateToday()
            await fetch()
        } catch {
            model.handle(error)
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Add / edit sheet

private struct GoalFormSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let goal: GoalDTO?
    let areas: [AreaDTO]
    var onSave: (_ title: String, _ description: String?, _ areaId: String?) async throws -> Void

    @State private var title = ""
    @State private var details = ""
    @State private var areaId: String?
    @State private var isSaving = false
    @State private var errorMessage: String?

    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($titleFocused)
                    TextField("Description (optional)", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Picker("Area", selection: $areaId) {
                        Text("None").tag(String?.none)
                        ForEach(areas) { area in
                            Text(area.name).tag(Optional(area.id))
                        }
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadJ)
                            .foregroundStyle(Color.danger)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let goal {
                    title = goal.title
                    details = goal.description ?? ""
                    areaId = goal.areaId
                }
                titleFocused = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 320)
        #endif
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
                try await onSave(trimmedTitle, trimmedDetails.isEmpty ? nil : trimmedDetails, areaId)
                dismiss()
            } catch {
                model.handle(error)
                errorMessage = error.localizedDescription
            }
        }
    }
}
