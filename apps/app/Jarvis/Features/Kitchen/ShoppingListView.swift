import DesignSystem
import JarvisAPI
import SwiftUI

/// The shopping list.
///
/// This screen is used in exactly two places: on the sofa, adding the thing
/// you just ran out of, and in a shop, one-handed, ticking things off. So the
/// add field is always open and keeps focus after every return (you add three
/// things in a row, not one), and the whole row is the tick target rather than
/// a checkbox you have to aim at with a trolley in the other hand.
struct ShoppingListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    let store: ShoppingStore

    @State private var draft = ""
    @FocusState private var addFieldFocused: Bool
    @State private var editing: ShoppingItemDTO?
    @State private var showClearAllConfirm = false

    var body: some View {
        List {
            Group {
                addRow
                if let error = store.actionError {
                    inlineError(error)
                }
                if store.isEmpty {
                    if case .loading = store.state {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Space.xxxl)
                    } else if case .failed(let message) = store.state {
                        failure(message)
                    } else {
                        emptyState
                    }
                } else {
                    remainingSection
                    pickedSection
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: 3, leading: PageMargin.standard,
                bottom: 3, trailing: PageMargin.standard,
            ))
            #if os(macOS)
            .frame(maxWidth: PageMargin.contentMaxWidth)
            .frame(maxWidth: .infinity)
            #endif
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bgCanvas)
        .refreshable { await store.load(force: true) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Clear picked up", systemImage: "checkmark.circle") {
                        withJarvisAnimation { store.clearPicked() }
                        Haptics.play(.medium)
                    }
                    .disabled(store.picked.isEmpty)
                    Divider()
                    Button("Clear whole list", systemImage: "trash", role: .destructive) {
                        showClearAllConfirm = true
                    }
                    .disabled(store.isEmpty)
                } label: {
                    Label("List options", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Clear the whole list?",
            isPresented: $showClearAllConfirm,
            titleVisibility: .visible,
        ) {
            Button("Clear everything", role: .destructive) {
                withJarvisAnimation { store.clearAll() }
                Haptics.play(.warning)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all \(store.items.count) items, picked up or not.")
        }
        .sheet(item: $editing) { item in
            ShoppingItemEditor(item: item, store: store)
        }
        .task {
            store.bind(model)
            await store.load()
        }
        .onChange(of: model.dataRevision) {
            Task { await store.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
    }

    // MARK: - Add

    private var addRow: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 22)

            TextField("Add an item", text: $draft)
                .textFieldStyle(.plain)
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .focused($addFieldFocused)
                .submitLabel(.done)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                #endif
                // Keeps focus so a second and third item need no extra tap.
                .onSubmit(submit)

            if !draft.isEmpty {
                Button("Add", action: submit)
                    .buttonStyle(.jarvisSoft)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: RowHeight.standard)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(
                    addFieldFocused ? Color.accentPrimary.opacity(0.5) : Color.borderHairline,
                    lineWidth: 1,
                ),
        )
        .jarvisShadow(.card)
        .jarvisAnimation(Motion.quick, value: draft.isEmpty)
        .jarvisAnimation(Motion.quick, value: addFieldFocused)
        .padding(.bottom, Space.xs)
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withJarvisAnimation { store.add(text) }
        draft = ""
        Haptics.play(.light)
        addFieldFocused = true
    }

    // MARK: - Sections

    @ViewBuilder
    private var remainingSection: some View {
        if !store.remaining.isEmpty {
            SectionHeader("To buy", subtitle: countLabel)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.xs)
            ForEach(store.remaining) { item in
                itemRow(item)
            }
        } else if !store.isEmpty {
            allDoneBanner
        }
    }

    private var countLabel: String {
        let remaining = store.remaining.count
        let total = store.items.count
        return total == remaining ? "\(total) items" : "\(remaining) of \(total) left"
    }

    @ViewBuilder
    private var pickedSection: some View {
        if !store.picked.isEmpty {
            SectionHeader("In the trolley", subtitle: "\(store.picked.count)") {
                Button("Clear") {
                    withJarvisAnimation { store.clearPicked() }
                    Haptics.play(.medium)
                }
                .buttonStyle(.jarvisSoft)
            }
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xs)
            ForEach(store.picked) { item in
                itemRow(item)
            }
        }
    }

    private var allDoneBanner: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.success)
            Text("Everything on the list is in the trolley.")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(Space.lg)
        .background(Color.successSubtle, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.top, Space.sm)
    }

    // MARK: - Row

    private func itemRow(_ item: ShoppingItemDTO) -> some View {
        HStack(spacing: Space.md) {
            // The circle draws the state; the tap is owned by the whole row
            // below, so it deliberately does nothing of its own.
            CheckCircle(isOn: item.checked, tint: ItemColor.green.color) {}
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.headlineJ)
                    .foregroundStyle(item.checked ? Color.textTertiary : Color.textPrimary)
                    .strikethrough(item.checked, color: Color.textTertiary)
                    .lineLimit(2)
                if let quantity = item.quantity, !quantity.isEmpty {
                    Text(quantity)
                        .font(.subheadJ)
                        .foregroundStyle(item.checked ? Color.textTertiary : Color.textSecondary)
                }
            }
            Spacer(minLength: Space.sm)
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: RowHeight.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(Color.borderHairline, lineWidth: 0.5),
        )
        .jarvisShadow(.card)
        .opacity(item.checked ? 0.62 : 1)
        // The whole row is the target: one thumb, trolley in the other hand.
        .pressable(haptic: item.checked ? .light : .success) {
            withJarvisAnimation { store.setChecked(item, !item.checked) }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editing = item }
            Button("Delete", systemImage: "trash", role: .destructive) {
                withJarvisAnimation { store.delete(item) }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                withJarvisAnimation { store.delete(item) }
            }
        }
        .swipeActions(edge: .leading) {
            Button("Edit", systemImage: "pencil") { editing = item }
                .tint(ItemColor.blue.color)
        }
    }

    // MARK: - States

    private var emptyState: some View {
        EmptyState(
            symbol: "cart",
            title: "Nothing on the list",
            message: "Add things the moment you think of them. Type \"2 kg chicken\" and the amount is picked up automatically.",
            tint: ItemColor.teal.color,
        ) {
            Button("Add the first item") { addFieldFocused = true }
                .buttonStyle(.jarvisPrimary)
        }
        .padding(.top, Space.xl)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: Space.lg) {
            Text(message)
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await store.load(force: true) } }
                .buttonStyle(.jarvisSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxxl)
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: Space.sm) {
            Text(message)
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
            Spacer(minLength: Space.sm)
            Button("Dismiss") { store.actionError = nil }
                .buttonStyle(.plain)
                .font(.subheadJ)
                .foregroundStyle(Color.accentPrimary)
        }
        .padding(Space.md)
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }
}

/// Rename an item or fix its amount.
private struct ShoppingItemEditor: View {
    @Environment(\.dismiss) private var dismiss

    let item: ShoppingItemDTO
    let store: ShoppingStore

    @State private var name = ""
    @State private var quantity = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item", text: $name)
                    TextField("Amount (optional)", text: $quantity)
                } footer: {
                    Text("The amount is free text — \"2 kg\", \"3x\", \"a big one\".")
                        .font(.captionJ)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.rename(item, name: name, quantity: quantity)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            name = item.name
            quantity = item.quantity ?? ""
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 220)
        #endif
    }
}
