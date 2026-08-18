import Foundation

// Shopping list and meal prep endpoints.

public struct ShoppingItemCreateRequest: Encodable, Sendable {
    public var id: String?
    public var name: String
    public var quantity: String?

    public init(id: String? = nil, name: String, quantity: String? = nil) {
        self.id = id
        self.name = name
        self.quantity = quantity
    }
}

public struct ShoppingBulkAddRequest: Encodable, Sendable {
    public struct Item: Encodable, Sendable {
        public var id: String?
        public var name: String
        public var quantity: String?

        public init(id: String? = nil, name: String, quantity: String? = nil) {
            self.id = id
            self.name = name
            self.quantity = quantity
        }
    }

    public var items: [Item]

    public init(items: [Item]) {
        self.items = items
    }
}

public struct MealIngredientInput: Encodable, Sendable, Equatable {
    public var name: String
    public var quantity: String?

    public init(name: String, quantity: String? = nil) {
        self.name = name
        self.quantity = quantity
    }
}

public struct MealPrepRequest: Encodable, Sendable {
    public var id: String?
    public var name: String
    public var description: String?
    public var instructions: String?
    public var prepMinutes: Int?
    public var portions: Int?
    public var basis: String?
    public var calories: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public var ingredients: [MealIngredientInput]?

    public init(
        id: String? = nil,
        name: String,
        description: String? = nil,
        instructions: String? = nil,
        prepMinutes: Int? = nil,
        portions: Int? = nil,
        basis: String? = nil,
        calories: Double? = nil,
        proteinG: Double? = nil,
        carbsG: Double? = nil,
        fatG: Double? = nil,
        ingredients: [MealIngredientInput]? = nil,
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.instructions = instructions
        self.prepMinutes = prepMinutes
        self.portions = portions
        self.basis = basis
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.ingredients = ingredients
    }
}

private struct ScopeBody: Encodable, Sendable {
    let scope: String
}

extension APIClient {
    // MARK: Shopping list

    public func shoppingItems() async throws -> ShoppingListResponse {
        try await get(ShoppingListResponse.self, "/shopping-items")
    }

    public func createShoppingItem(_ request: ShoppingItemCreateRequest) async throws -> ShoppingItemDTO {
        try await post(ShoppingItemDTO.self, "/shopping-items", body: request)
    }

    public func patchShoppingItem(id: String, _ patch: JSONObject) async throws -> ShoppingItemDTO {
        try await self.patch(ShoppingItemDTO.self, "/shopping-items/\(id)", body: patch)
    }

    public func deleteShoppingItem(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/shopping-items/\(id)")
    }

    /// `scope: "checked"` clears what is already in the trolley; `"all"` empties it.
    public func clearShoppingItems(scope: String = "checked") async throws -> OkResponse {
        try await post(OkResponse.self, "/shopping-items/clear", body: ScopeBody(scope: scope))
    }

    public func addShoppingItems(_ request: ShoppingBulkAddRequest) async throws -> ShoppingBulkAddResponse {
        try await post(ShoppingBulkAddResponse.self, "/shopping-items/bulk", body: request)
    }

    // MARK: Meal preps

    public func mealPreps() async throws -> MealPrepListResponse {
        try await get(MealPrepListResponse.self, "/meal-preps")
    }

    public func mealPrep(id: String) async throws -> MealPrepDTO {
        try await get(MealPrepDTO.self, "/meal-preps/\(id)")
    }

    public func createMealPrep(_ request: MealPrepRequest) async throws -> MealPrepDTO {
        try await post(MealPrepDTO.self, "/meal-preps", body: request)
    }

    public func patchMealPrep(id: String, _ request: MealPrepRequest) async throws -> MealPrepDTO {
        try await patch(MealPrepDTO.self, "/meal-preps/\(id)", body: request)
    }

    public func deleteMealPrep(id: String) async throws -> OkResponse {
        try await delete(OkResponse.self, "/meal-preps/\(id)")
    }

    public func uploadMealPhoto(id: String, data: Data, contentType: String) async throws -> MealPrepDTO {
        try await upload(MealPrepDTO.self, "/meal-preps/\(id)/photo", data: data, contentType: contentType)
    }

    public func deleteMealPhoto(id: String) async throws -> MealPrepDTO {
        try await delete(MealPrepDTO.self, "/meal-preps/\(id)/photo")
    }
}
