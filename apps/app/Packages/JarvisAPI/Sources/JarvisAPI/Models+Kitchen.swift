import Foundation

// Shopping list and meal prep DTOs.

public struct ShoppingItemDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let quantity: String?
    public let checked: Bool
    public let checkedAt: String?
    public let sortOrder: Int
    public let createdAt: String

    public init(
        id: String,
        name: String,
        quantity: String? = nil,
        checked: Bool = false,
        checkedAt: String? = nil,
        sortOrder: Int = 0,
        createdAt: String = "",
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.checked = checked
        self.checkedAt = checkedAt
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// Optimistic local flip — the server write is queued separately.
    public func toggled(_ isChecked: Bool) -> ShoppingItemDTO {
        ShoppingItemDTO(
            id: id,
            name: name,
            quantity: quantity,
            checked: isChecked,
            checkedAt: isChecked ? (checkedAt ?? ISO8601DateFormatter().string(from: .now)) : nil,
            sortOrder: sortOrder,
            createdAt: createdAt,
        )
    }
}

public struct ShoppingListResponse: Codable, Sendable {
    public let items: [ShoppingItemDTO]
}

public struct ShoppingBulkAddResponse: Codable, Sendable {
    public let added: Int
    public let skipped: Int
    public let items: [ShoppingItemDTO]
}

// MARK: - Meal preps

public struct MealIngredientDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let quantity: String?
    public let sortOrder: Int

    /// "1 kg Chicken breast" — quantity first, the way a shopping list reads.
    public var line: String {
        guard let quantity, !quantity.isEmpty else { return name }
        return "\(quantity) \(name)"
    }
}

public struct MacrosDTO: Codable, Sendable, Equatable {
    public let calories: Double?
    public let proteinG: Double?
    public let carbsG: Double?
    public let fatG: Double?

    public var isEmpty: Bool {
        calories == nil && proteinG == nil && carbsG == nil && fatG == nil
    }
}

public enum MacrosBasis: String, Codable, Sendable, CaseIterable {
    case portion
    case total
}

public struct MealPrepDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String?
    public let instructions: String?
    public let prepMinutes: Int?
    public let portions: Int
    /// Which of the two macro blocks the user actually typed in; the other is
    /// derived server-side, so both are always populated and always agree.
    public let basis: MacrosBasis
    public let perPortion: MacrosDTO
    public let total: MacrosDTO
    public let photoUrl: String?
    public let hasPhoto: Bool
    public let ingredients: [MealIngredientDTO]
    public let sortOrder: Int
    public let createdAt: String
    public let updatedAt: String
}

public struct MealPrepListResponse: Codable, Sendable {
    public let mealPreps: [MealPrepDTO]
}
