import DesignSystem
import JarvisAPI
import SwiftUI

/// Minimal Stage-1 areas editor: list, add, rename, delete.
struct AreasEditorView: View {
    @Environment(AppModel.self) private var model

    @State private var state: LoadState<[AreaDTO]> = .idle
    @State private var showingAdd = false
    @State private var editing: AreaDTO?
    @State private var pendingDelete: AreaDTO?
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
            case .loaded(let areas):
                let active = areas.filter { $0.archivedAt == nil }
                if active.isEmpty {
                    VStack(spacing: Space.md) {
                        Text("No areas yet")
                            .font(.bodyJ)
                            .foregroundStyle(Color.textSecondary)
                        Button("Add area") { showingAdd = true }
                            .buttonStyle(.jarvisGhost)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    areaList(active)
                }
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle("Areas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add area", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AreaFormSheet(area: nil) { name, emoji in
                try await model.api.createArea(AreaCreateRequest(name: name, emoji: emoji))
                model.invalidateToday()
                await fetch()
            }
        }
        .sheet(item: $editing) { area in
            AreaFormSheet(area: area) { name, emoji in
                try await model.api.patchArea(
                    id: area.id,
                    ["name": .string(name), "emoji": emoji.map { .string($0) } ?? .null],
                )
                model.invalidateToday()
                await fetch()
            }
        }
        .confirmationDialog(
            "Delete area",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } },
            ),
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) {
                if let area = pendingDelete {
                    Task { await delete(area) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Habits linked to this area keep working. They just lose their grouping.")
        }
        .task { await fetch() }
    }

    private func areaList(_ areas: [AreaDTO]) -> some View {
        List {
            if let actionError {
                Text(actionError)
                    .font(.subheadJ)
                    .foregroundStyle(Color.danger)
                    .listRowBackground(Color.bgCanvas)
                    .listRowSeparator(.hidden)
            }
            ForEach(areas) { area in
                HStack(spacing: Space.md) {
                    Text(area.emoji ?? "•")
                    Text(area.name)
                        .font(.bodyJ)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { editing = area }
                .frame(minHeight: RowHeight.standard)
                .listRowBackground(Color.bgCanvas)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = area
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button("Rename") { editing = area }
                    Button("Delete", role: .destructive) { pendingDelete = area }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await fetch() }
    }

    private func fetch() async {
        if state.value == nil { state = .loading }
        do {
            let response = try await model.api.areas()
            state = .loaded(response.areas)
            actionError = nil
        } catch {
            model.handle(error)
            state = .failed(error.localizedDescription)
        }
    }

    private func delete(_ area: AreaDTO) async {
        do {
            _ = try await model.api.deleteArea(id: area.id)
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

// MARK: - Add / rename sheet

private struct AreaFormSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let area: AreaDTO?
    var onSave: (_ name: String, _ emoji: String?) async throws -> Void

    @State private var name = ""
    @State private var emoji = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                    TextField("Emoji (optional)", text: $emoji)
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
            .navigationTitle(area == nil ? "New area" : "Edit area")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let area {
                    name = area.name
                    emoji = area.emoji ?? ""
                }
                nameFocused = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 240)
        #endif
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                let trimmedEmoji = emoji.trimmingCharacters(in: .whitespaces)
                try await onSave(trimmedName, trimmedEmoji.isEmpty ? nil : trimmedEmoji)
                dismiss()
            } catch {
                model.handle(error)
                errorMessage = error.localizedDescription
            }
        }
    }
}
