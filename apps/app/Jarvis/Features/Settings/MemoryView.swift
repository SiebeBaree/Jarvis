import DesignSystem
import JarvisAPI
import SwiftUI

/// "What J.A.R.V.I.S. knows": every stored memory, grouped by category —
/// fully editable. Facts arrive automatically after conversations; this
/// screen is the user's window and veto.
struct MemoryView: View {
    @Environment(AppModel.self) private var model

    @State private var memories: LoadState<[MemoryDTO]> = .idle
    @State private var editing: MemoryDTO?
    @State private var isAdding = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if let items = memories.value {
                content(items)
            } else if case .failed(let message) = memories {
                errorState(message)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle("What J.A.R.V.I.S. knows")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add memory")
            }
        }
        .sheet(item: $editing) { memory in
            MemoryEditorSheet(memory: memory) { category, content in
                await save(id: memory.id, category: category, content: content)
            }
        }
        .sheet(isPresented: $isAdding) {
            MemoryEditorSheet(memory: nil) { category, content in
                await save(id: nil, category: category, content: content)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ items: [MemoryDTO]) -> some View {
        if items.isEmpty {
            emptyState
        } else {
            List {
                if let errorText {
                    Text(errorText)
                        .font(.subheadJ)
                        .foregroundStyle(Color.danger)
                        .listRowBackground(Color.clear)
                }
                ForEach(MemoryCategory.allCases, id: \.self) { category in
                    let grouped = items.filter { $0.category == category.rawValue }
                    if !grouped.isEmpty {
                        Section {
                            ForEach(grouped) { memory in
                                row(memory)
                            }
                        } header: {
                            Label(category.title, systemImage: category.icon)
                                .font(.captionJ)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                Section {
                    EmptyView()
                } footer: {
                    Text("J.A.R.V.I.S. updates this automatically after conversations. Edit or delete anything — it only knows what is on this list.")
                        .font(.captionJ)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
        }
    }

    private func row(_ memory: MemoryDTO) -> some View {
        Text(memory.content)
            .font(.bodyJ)
            .foregroundStyle(Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .onTapGesture { editing = memory }
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) {
                    Task { await remove(memory) }
                }
            }
            .contextMenu {
                Button("Edit") { editing = memory }
                Button("Delete", role: .destructive) {
                    Task { await remove(memory) }
                }
            }
    }

    private var emptyState: some View {
        VStack(spacing: Space.lg) {
            Image(systemName: "brain")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.textTertiary)
            Text("Nothing stored yet")
                .font(.title2J)
                .foregroundStyle(Color.textPrimary)
            Text("Talk to J.A.R.V.I.S. — it remembers durable facts about you automatically. You can also add facts yourself.")
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Add a fact") { isAdding = true }
                .buttonStyle(.jarvisSecondary)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Space.lg) {
            Text(message)
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
            Button("Retry") {
                Task { await load() }
            }
            .buttonStyle(.jarvisSecondary)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func load() async {
        do {
            memories = .loaded(try await model.api.memories().memories)
        } catch {
            model.handle(error)
            if memories.value == nil { memories = .failed(TodayStore.message(for: error)) }
        }
    }

    private func save(id: String?, category: String, content: String) async {
        errorText = nil
        do {
            if let id {
                _ = try await model.api.patchMemory(id: id, [
                    "category": .string(category),
                    "content": .string(content),
                ])
            } else {
                _ = try await model.api.createMemory(category: category, content: content)
            }
            await load()
        } catch {
            model.handle(error)
            errorText = TodayStore.message(for: error)
        }
    }

    private func remove(_ memory: MemoryDTO) async {
        errorText = nil
        do {
            _ = try await model.api.deleteMemory(id: memory.id)
            await load()
        } catch {
            model.handle(error)
            errorText = TodayStore.message(for: error)
        }
    }
}

// MARK: - Editor sheet

private struct MemoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let memory: MemoryDTO?
    let onSave: (String, String) async -> Void

    @State private var category: MemoryCategory = .context
    @State private var content = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $category) {
                    ForEach(MemoryCategory.allCases, id: \.self) { category in
                        Text(category.title).tag(category)
                    }
                }
                TextField("One concise fact", text: $content, axis: .vertical)
                    .lineLimit(2...5)
            }
            .formStyle(.grouped)
            .navigationTitle(memory == nil ? "Add memory" : "Edit memory")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        isSaving = true
                        Task {
                            await onSave(category.rawValue, trimmed)
                            dismiss()
                        }
                    }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .onAppear {
            if let memory {
                category = MemoryCategory(rawValue: memory.category) ?? .context
                content = memory.content
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 280)
        #endif
    }
}
