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
    @State private var description = ""
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
            Form {
                photoSection
                detailsSection
                macrosSection
                ingredientsSection
                instructionsSection
                if let errorText {
                    Text(errorText)
                        .font(.subheadJ)
                        .foregroundStyle(Color.danger)
                }
            }
            .formStyle(.grouped)
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
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }

    // MARK: - Sections

    private var photoSection: some View {
        Section {
            HStack(spacing: Space.lg) {
                previewPhoto
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

                VStack(alignment: .leading, spacing: Space.sm) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Text(hasAnyPhoto ? "Change photo" : "Add a photo")
                            .font(.subheadStrongJ)
                    }
                    if hasAnyPhoto {
                        Button("Remove", role: .destructive) {
                            pickedPhoto = nil
                            pickerItem = nil
                            if let editing, editing.hasPhoto {
                                Task { await store.removePhoto(id: editing.id) }
                            }
                        }
                        .font(.subheadJ)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.xs)
        } footer: {
            Text("A photo of the finished batch, so you can see what it should look like next time.")
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var hasAnyPhoto: Bool {
        pickedPhoto != nil || (editing?.hasPhoto ?? false)
    }

    @ViewBuilder
    private var previewPhoto: some View {
        if let pickedPhoto, let image = PlatformImage.from(pickedPhoto) {
            image.resizable().scaledToFill()
        } else {
            MealPhoto(url: editing?.photoUrl, height: 88, cornerRadius: Radius.control)
        }
    }

    private var detailsSection: some View {
        Section("The meal") {
            TextField("Name", text: $name)
            TextField("Short description (optional)", text: $description, axis: .vertical)
                .lineLimit(1...3)
            HStack {
                Text("Prep time")
                Spacer()
                TextField("45", text: $prepMinutes)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Text("min").foregroundStyle(Color.textSecondary)
            }
            Stepper("Portions: \(portions)", value: $portions, in: 1...50)
        }
    }

    private var macrosSection: some View {
        Section {
            Picker("These numbers are", selection: $basis) {
                Text("For the whole batch").tag(MacrosBasis.total)
                Text("Per portion").tag(MacrosBasis.portion)
            }
            .pickerStyle(.segmented)

            macroField("Calories", text: $calories, unit: "kcal")
            macroField("Protein", text: $protein, unit: "g")
            macroField("Carbs", text: $carbs, unit: "g")
            macroField("Fat", text: $fat, unit: "g")
        } header: {
            Text("Macros")
        } footer: {
            Text(macroFooter)
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
        }
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

    private func macroField(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(unit)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 34, alignment: .leading)
        }
    }

    private var ingredientsSection: some View {
        Section("Ingredients") {
            ForEach($ingredients) { $ingredient in
                HStack(spacing: Space.sm) {
                    TextField("Ingredient", text: $ingredient.name)
                    TextField("Amount", text: $ingredient.quantity)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 82)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .onDelete { offsets in
                ingredients.remove(atOffsets: offsets)
                if ingredients.isEmpty { ingredients = [IngredientDraft()] }
            }
            .onMove { source, destination in
                ingredients.move(fromOffsets: source, toOffset: destination)
            }

            Button {
                withJarvisAnimation { ingredients.append(IngredientDraft()) }
            } label: {
                Label("Add ingredient", systemImage: "plus.circle")
            }
        }
    }

    private var instructionsSection: some View {
        Section {
            TextField("How do you make it?", text: $instructions, axis: .vertical)
                .lineLimit(4...14)
        } header: {
            Text("Method")
        } footer: {
            Text("Write it however you think about it — one line or ten steps.")
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Load & save

    private func loadEditing() {
        guard !didLoad, let editing else { return }
        didLoad = true
        name = editing.name
        description = editing.description ?? ""
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
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
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
