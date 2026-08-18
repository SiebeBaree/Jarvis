import DesignSystem
import JarvisAPI
import PhotosUI
import SwiftUI

/// Create or edit a meal prep.
///
/// The macro block asks *how* the numbers were worked out rather than assuming.
/// People read totals off a recipe or a packet, and quietly treating a batch
/// total as one portion is the kind of error you only notice weeks later.
struct MealPrepEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let store: MealsStore
    var editing: MealPrepDTO?

    @State private var name = ""
    @State private var summary = ""
    @State private var instructions = ""
    @State private var prepMinutes = ""
    @State private var portions = 4
    @State private var basis: MacrosBasis = .total
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var ingredients: [IngredientDraft] = [IngredientDraft()]

    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedPhoto: Data?
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var didLoad = false

    private struct IngredientDraft: Identifiable, Equatable {
        let id = UUID()
        var name = ""
        var quantity = ""

        var isBlank: Bool {
            name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    photoCard
                    detailsCard
                    macrosCard
                    ingredientsCard
                    methodCard
                    if let errorText {
                        Text(errorText)
                            .font(.subheadJ)
                            .foregroundStyle(Color.danger)
                    }
                }
                .padding(PageMargin.standard)
            }
            .background(Color.bgCanvas)
            .navigationTitle(editing == nil ? "New meal prep" : "Edit meal prep")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Save", action: save).disabled(!canSave)
                    }
                }
            }
        }
        .onAppear(perform: loadEditing)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                pickedPhoto = try? await item.loadTransferable(type: Data.self)
                if pickedPhoto == nil { errorText = "That image could not be read." }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, idealWidth: 660, minHeight: 640, idealHeight: 720)
        #endif
    }

    // MARK: - Photo

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.lg) {
                previewPhoto
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

                VStack(alignment: .leading, spacing: Space.sm) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Text(hasAnyPhoto ? "Change photo" : "Add a photo")
                            .font(.subheadStrongJ)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentPrimary)

                    if hasAnyPhoto {
                        Button("Remove") {
                            pickedPhoto = nil
                            pickerItem = nil
                            if let editing, editing.hasPhoto {
                                Task { await store.removePhoto(id: editing.id) }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.subheadJ)
                        .foregroundStyle(Color.danger)
                    }

                    Text("So you can see what the batch should look like next time.")
                        .font(.captionJ)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private var hasAnyPhoto: Bool {
        pickedPhoto != nil || (editing?.hasPhoto ?? false)
    }

    @ViewBuilder
    private var previewPhoto: some View {
        if let pickedPhoto, let image = PlatformImage.from(pickedPhoto) {
            image.resizable().scaledToFill()
        } else {
            MealPhoto(url: editing?.photoUrl, height: 92, cornerRadius: Radius.control)
        }
    }

    // MARK: - Details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("The meal")

            boxed { PromptField(prompt: "Name", text: $name) }
            boxed {
                PromptField(
                    prompt: "Short description (optional)",
                    text: $summary,
                    axis: .vertical,
                    lineLimit: 1...3,
                )
            }

            HStack(alignment: .bottom, spacing: Space.lg) {
                CaptionedField(
                    caption: "Prep time",
                    prompt: "45",
                    text: $prepMinutes,
                    width: 66,
                    suffix: "min",
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Portions")
                        .font(.microJ)
                        .foregroundStyle(Color.textTertiary)
                    Stepper(value: $portions, in: 1...50) {
                        Text("\(portions)")
                            .font(.numeralJ)
                            .foregroundStyle(Color.textPrimary)
                            .frame(minWidth: 22)
                    }
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Macros

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Macros")

            Picker("", selection: $basis) {
                Text("Whole batch").tag(MacrosBasis.total)
                Text("Per portion").tag(MacrosBasis.portion)
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            VStack(spacing: Space.sm) {
                LabeledField(label: "Calories", prompt: "0", text: $calories, unit: "kcal")
                Divider().overlay(Color.borderHairline)
                LabeledField(label: "Protein", prompt: "0", text: $protein, unit: "g")
                Divider().overlay(Color.borderHairline)
                LabeledField(label: "Carbs", prompt: "0", text: $carbs, unit: "g")
                Divider().overlay(Color.borderHairline)
                LabeledField(label: "Fat", prompt: "0", text: $fat, unit: "g")
            }

            Text(macroFooter)
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    /// Shows the conversion live, so a mis-set basis is obvious before saving.
    private var macroFooter: String {
        guard let value = Double(calories.replacingOccurrences(of: ",", with: ".")), value > 0 else {
            return "Enter them whichever way you worked them out. Both views are shown on the meal."
        }
        let perPortion = basis == .total ? value / Double(max(1, portions)) : value
        let total = basis == .total ? value : value * Double(portions)
        return "That is \(Int(perPortion.rounded())) kcal per portion, \(Int(total.rounded())) kcal for all \(portions)."
    }

    // MARK: - Ingredients

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Ingredients")

            ForEach($ingredients) { $ingredient in
                HStack(spacing: Space.sm) {
                    boxed { PromptField(prompt: "Ingredient", text: $ingredient.name) }

                    // Wide enough for "500 g" and "2 tbsp" without the hint
                    // truncating, which is what "Amou / nt" was.
                    boxed { PromptField(prompt: "Amount", text: $ingredient.quantity) }
                        .frame(width: 110)

                    Button {
                        withJarvisAnimation {
                            ingredients.removeAll { $0.id == ingredient.id }
                            if ingredients.isEmpty { ingredients = [IngredientDraft()] }
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove ingredient")
                }
            }

            Button {
                withJarvisAnimation { ingredients.append(IngredientDraft()) }
            } label: {
                Label("Add ingredient", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.jarvisSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Method

    private var methodCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Method")
            boxed {
                PromptField(
                    prompt: "How do you make it?",
                    text: $instructions,
                    axis: .vertical,
                    lineLimit: 4...14,
                )
            }
            Text("Write it however you think about it, one line or ten steps.")
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    /// Shared field chrome, so every input on the sheet is the same object.
    private func boxed(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .frame(minHeight: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.bgSubtle,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous),
            )
    }

    // MARK: - Load & save

    private func loadEditing() {
        guard !didLoad, let editing else { return }
        didLoad = true
        name = editing.name
        summary = editing.description ?? ""
        instructions = editing.instructions ?? ""
        prepMinutes = editing.prepMinutes.map(String.init) ?? ""
        portions = editing.portions
        basis = editing.basis
        let macros = editing.basis == .total ? editing.total : editing.perPortion
        calories = Self.text(macros.calories)
        protein = Self.text(macros.proteinG)
        carbs = Self.text(macros.carbsG)
        fat = Self.text(macros.fatG)
        ingredients = editing.ingredients.isEmpty
            ? [IngredientDraft()]
            : editing.ingredients.map { IngredientDraft(name: $0.name, quantity: $0.quantity ?? "") }
    }

    private static func text(_ value: Double?) -> String {
        guard let value else { return "" }
        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func number(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        errorText = nil

        let request = MealPrepRequest(
            name: trimmedName,
            description: summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            prepMinutes: Int(prepMinutes.trimmingCharacters(in: .whitespaces)),
            portions: portions,
            basis: basis.rawValue,
            calories: Self.number(calories),
            proteinG: Self.number(protein),
            carbsG: Self.number(carbs),
            fatG: Self.number(fat),
            ingredients: ingredients
                .filter { !$0.isBlank }
                .map {
                    MealIngredientInput(
                        name: $0.name.trimmingCharacters(in: .whitespaces),
                        quantity: $0.quantity.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                    )
                },
        )

        Task {
            let saved: MealPrepDTO?
            if let editing {
                saved = await store.update(id: editing.id, request, photo: pickedPhoto)
            } else {
                saved = await store.create(request, photo: pickedPhoto)
            }
            isSaving = false
            if saved != nil {
                Haptics.play(.success)
                dismiss()
            } else {
                errorText = store.actionError ?? "Could not save. Try again."
            }
        }
    }
}

extension String {
    /// Empty strings from a text field mean "not set", not "set to nothing".
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Cross-platform "show these bytes as an Image" for the local photo preview,
/// before it has been uploaded and has a URL.
enum PlatformImage {
    static func from(_ data: Data) -> Image? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}
