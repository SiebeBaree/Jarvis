import DesignSystem
import JarvisAPI
import SwiftUI

/// Create or edit one improvement area.
struct AreaEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let store: ImproveStore
    var editing: ImprovementAreaDTO?

    @State private var name = ""
    @State private var emoji = ""
    @State private var betterLooksLike = ""
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Space.md) {
                        TextField("🏷️", text: $emoji)
                            .frame(width: 44)
                        TextField("Area (posture, clothing, …)", text: $name)
                    }
                    TextField("What does better look like?", text: $betterLooksLike, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("J.A.R.V.I.S. uses \"what better looks like\" to judge your weekly photos — the more concrete, the more useful its feedback.")
                        .font(.captionJ)
                        .foregroundStyle(Color.textTertiary)
                }
                if let errorText {
                    Text(errorText)
                        .font(.subheadJ)
                        .foregroundStyle(Color.danger)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? "New area" : "Edit area")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .onAppear {
            if let editing {
                name = editing.name
                emoji = editing.emoji ?? ""
                betterLooksLike = editing.betterLooksLike ?? ""
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 320)
        #endif
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespaces)
        let trimmedBetter = betterLooksLike.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        errorText = nil
        Task {
            let ok: Bool
            if let editing {
                ok = await store.updateArea(
                    id: editing.id,
                    name: trimmedName,
                    emoji: trimmedEmoji.isEmpty ? nil : trimmedEmoji,
                    betterLooksLike: trimmedBetter.isEmpty ? nil : trimmedBetter,
                )
            } else {
                ok = await store.createArea(
                    name: trimmedName,
                    emoji: trimmedEmoji.isEmpty ? nil : trimmedEmoji,
                    betterLooksLike: trimmedBetter.isEmpty ? nil : trimmedBetter,
                )
            }
            isSaving = false
            if ok {
                dismiss()
            } else {
                errorText = store.mutationError ?? "Could not save — try again."
            }
        }
    }
}
