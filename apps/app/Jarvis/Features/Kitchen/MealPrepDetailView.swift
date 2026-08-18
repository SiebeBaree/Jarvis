import DesignSystem
import JarvisAPI
import SwiftUI

/// One meal prep: the photo, what goes in it, how to make it, and what it
/// comes to. The macro block flips between one portion and the whole batch,
/// because both are real questions ("what am I eating now" vs "did the batch
/// hit my week's protein") and the server sends both.
struct MealPrepDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let mealId: String
    let store: MealsStore
    let shopping: ShoppingStore

    @State private var showsTotal = false
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var isSendingToList = false

    private var meal: MealPrepDTO? { store.meal(withId: mealId) }

    var body: some View {
        Group {
            if let meal {
                content(meal)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle(meal?.name ?? "Meal prep")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { showEditor = true }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        showDeleteConfirm = true
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let meal {
                MealPrepEditorView(store: store, editing: meal)
            }
        }
        .confirmationDialog(
            "Delete this meal prep?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    if await store.delete(id: mealId) { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Shopping list",
            isPresented: Binding(
                get: { store.shoppingConfirmation != nil },
                set: { if !$0 { store.shoppingConfirmation = nil } },
            ),
        ) {
            Button("OK") { store.shoppingConfirmation = nil }
        } message: {
            Text(store.shoppingConfirmation ?? "")
        }
    }

    @ViewBuilder
    private func content(_ meal: MealPrepDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                MealPhoto(url: meal.photoUrl, height: 210)

                header(meal)
                macroCard(meal)
                ingredientsCard(meal)
                instructionsCard(meal)
            }
            .padding(.horizontal, PageMargin.standard)
            .padding(.bottom, Space.xxxl)
            #if os(macOS)
            .frame(maxWidth: PageMargin.contentMaxWidth)
            .frame(maxWidth: .infinity)
            #endif
        }
        .refreshable { await store.load(force: true) }
    }

    private func header(_ meal: MealPrepDTO) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(meal.name)
                .font(.title1J)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let description = meal.description, !description.isEmpty {
                Text(description)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Space.sm) {
                if let minutes = meal.prepMinutes {
                    TagChip(durationLabel(minutes), symbol: "clock")
                }
                TagChip("\(meal.portions) portion\(meal.portions == 1 ? "" : "s")", symbol: "square.grid.2x2")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func durationLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    // MARK: - Macros

    @ViewBuilder
    private func macroCard(_ meal: MealPrepDTO) -> some View {
        let macros = showsTotal ? meal.total : meal.perPortion
        if !macros.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Text("Macros")
                        .font(.title3J)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: Space.sm)
                    ChipPicker(
                        [false, true],
                        selection: $showsTotal,
                        label: { $0 ? "Whole batch" : "Per portion" },
                    )
                }

                HStack(spacing: Space.sm) {
                    macroTile("kcal", macros.calories, ItemColor.amber, decimals: 0)
                    macroTile("Protein", macros.proteinG, ItemColor.rose, unit: "g")
                    macroTile("Carbs", macros.carbsG, ItemColor.blue, unit: "g")
                    macroTile("Fat", macros.fatG, ItemColor.violet, unit: "g")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisCard()
        }
    }

    private func macroTile(
        _ title: String,
        _ value: Double?,
        _ color: ItemColor,
        unit: String = "",
        decimals: Int = 1,
    ) -> some View {
        VStack(spacing: 2) {
            Text(value.map { format($0, decimals: decimals) + unit } ?? Placeholder.noValue)
                .font(.numeralJ)
                .foregroundStyle(value == nil ? Color.textTertiary : color.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.microJ)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.md)
        .background(color.soft, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    /// Whole numbers stay whole — "600 kcal", never "600.0 kcal".
    private func format(_ value: Double, decimals: Int) -> String {
        if decimals == 0 || value == value.rounded() {
            return String(Int(value.rounded()))
        }
        return String(format: "%.\(decimals)f", value)
    }

    // MARK: - Ingredients

    @ViewBuilder
    private func ingredientsCard(_ meal: MealPrepDTO) -> some View {
        if !meal.ingredients.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader("Ingredients", subtitle: "\(meal.ingredients.count)")

                VStack(spacing: 0) {
                    ForEach(Array(meal.ingredients.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                            Circle()
                                .fill(ItemColor.orange.color.opacity(0.5))
                                .frame(width: 5, height: 5)
                            Text(item.name)
                                .font(.bodyJ)
                                .foregroundStyle(Color.textPrimary)
                            Spacer(minLength: Space.sm)
                            if let quantity = item.quantity, !quantity.isEmpty {
                                Text(quantity)
                                    .font(.monoJ)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .padding(.vertical, Space.sm)
                        if index < meal.ingredients.count - 1 {
                            Divider().overlay(Color.borderHairline)
                        }
                    }
                }

                Button {
                    sendToList(meal)
                } label: {
                    if isSendingToList {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    } else {
                        Label("Add all to shopping list", systemImage: "cart.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.jarvisSecondary)
                .disabled(isSendingToList)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisCard()
        }
    }

    private func sendToList(_ meal: MealPrepDTO) {
        isSendingToList = true
        Task {
            await store.sendToShoppingList(meal, shopping: shopping)
            isSendingToList = false
            Haptics.play(.success)
        }
    }

    // MARK: - Instructions

    @ViewBuilder
    private func instructionsCard(_ meal: MealPrepDTO) -> some View {
        if let instructions = meal.instructions, !instructions.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader("How to make it")
                Text(instructions)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisCard()
        }
    }
}
