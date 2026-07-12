import DesignSystem
import JarvisAPI
import SwiftUI

/// Vision (§B3): document-like page — the vision statement (editable via a
/// sheet), plus per-area aspiration cards (Stage 2-lite: not yet linked).
/// You write your own vision; the empty state opens the editor.
struct VisionView: View {
    let store: PlanStore

    @Environment(AppModel.self) private var model

    @State private var showEditor = false

    private var vision: VisionDTO? { store.visionContent.value?.vision }
    private var hasVision: Bool {
        !(vision?.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var body: some View {
        Group {
            if let content = store.visionContent.value {
                if hasVision {
                    document(content)
                } else {
                    emptyState
                }
            } else if case .failed(let message) = store.visionContent {
                errorState(message)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle("Vision")
        .toolbar {
            if hasVision {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showEditor = true }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            VisionEditorSheet(store: store, initial: vision?.content ?? "")
        }
        .task {
            await store.loadVision()
        }
        .onChange(of: model.todayRevision) {
            Task { await store.loadVision(force: true) }
        }
    }

    // MARK: - Document

    private func document(_ content: PlanStore.VisionContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Vision")
                        .font(.title1J)
                        .foregroundStyle(Color.textPrimary)
                    if let updatedAt = content.vision.flatMap({ PlanDisplay.instantLabel($0.updatedAt) }) {
                        Text("Updated \(updatedAt)")
                            .font(.captionJ)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Text(content.vision?.content ?? "")
                    .font(.bodyJ)
                    .foregroundStyle(Color.textPrimary)
                    .lineSpacing(7)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !content.areas.isEmpty {
                    SectionHeader("Areas")
                    ForEach(content.areas.sorted(by: { $0.sortOrder < $1.sortOrder })) { area in
                        areaCard(area)
                    }
                }
            }
            .padding(PageMargin.standard)
            #if os(macOS)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            #endif
        }
        .refreshable { await store.loadVision(force: true) }
    }

    private func areaCard(_ area: AreaDTO) -> some View {
        HStack(spacing: Space.md) {
            Text(area.emoji ?? "•")
                .font(.system(size: 18))
                .frame(width: 32, height: 32)
                .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            Text(area.name)
                .font(.headlineJ)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard(padding: Space.md)
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        VStack(spacing: Space.lg) {
            Text("No vision yet")
                .font(.title2J)
                .foregroundStyle(Color.textPrimary)
            Text("Describe your dream life in your own words — J.A.R.V.I.S. reads it for context, but you write it.")
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Write your vision") {
                showEditor = true
            }
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
                Task { await store.loadVision(force: true) }
            }
            .buttonStyle(.jarvisSecondary)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Editor sheet

/// Full-size TextEditor sheet saving via PUT /vision.
private struct VisionEditorSheet: View {
    let store: PlanStore
    let initial: String

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false

    init(store: PlanStore, initial: String) {
        self.store = store
        self.initial = initial
        _text = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.bodyJ)
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .padding(PageMargin.standard)
                .background(Color.bgCanvas)
                .navigationTitle("Edit Vision")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 480)
        #endif
        .interactiveDismissDisabled(text != initial)
    }

    private func save() {
        isSaving = true
        Task {
            if await store.saveVision(text) {
                dismiss()
            }
            isSaving = false
        }
    }
}
