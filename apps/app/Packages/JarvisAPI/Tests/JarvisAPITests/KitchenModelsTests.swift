import Foundation
import Testing
@testable import JarvisAPI

@Suite struct KitchenModelsTests {
    private let decoder = JSONDecoder()

    @Test func decodesShoppingList() throws {
        let json = """
        {"items":[
          {"id":"i1","name":"Chicken","quantity":"1 kg","checked":true,
           "checkedAt":"2026-08-18T12:00:00.000Z","sortOrder":0,
           "createdAt":"2026-08-18T11:00:00.000Z"},
          {"id":"i2","name":"Rice","quantity":null,"checked":false,"checkedAt":null,
           "sortOrder":1,"createdAt":"2026-08-18T11:01:00.000Z"}]}
        """
        let list = try decoder.decode(ShoppingListResponse.self, from: Data(json.utf8))
        #expect(list.items[0].checked)
        #expect(list.items[1].checked == false)
        #expect(list.items[1].quantity == nil)
    }

    @Test func togglingIsLocalAndReversible() {
        let item = ShoppingItemDTO(id: "i1", name: "Rice", quantity: "500 g")
        let checked = item.toggled(true)
        #expect(checked.checked)
        #expect(checked.checkedAt != nil)
        // Same identity and payload — only the checked state moves.
        #expect(checked.id == item.id)
        #expect(checked.quantity == "500 g")

        let unchecked = checked.toggled(false)
        #expect(unchecked.checked == false)
        #expect(unchecked.checkedAt == nil)
    }

    @Test func decodesMealPrepWithBothMacroViews() throws {
        let json = """
        {"id":"m1","name":"Chicken rice bowls","description":"Weekly batch",
         "instructions":"1. Cook rice.\\n2. Bake the chicken.","prepMinutes":45,"portions":4,
         "basis":"total",
         "perPortion":{"calories":600,"proteinG":50,"carbsG":60,"fatG":15},
         "total":{"calories":2400,"proteinG":200,"carbsG":240,"fatG":60},
         "photoUrl":"https://blob.example/meals/x.jpg","hasPhoto":true,
         "ingredients":[
           {"id":"g1","name":"Chicken breast","quantity":"1 kg","sortOrder":0},
           {"id":"g2","name":"Broccoli","quantity":null,"sortOrder":1}],
         "sortOrder":0,"createdAt":"2026-08-18T11:00:00.000Z",
         "updatedAt":"2026-08-18T11:00:00.000Z"}
        """
        let meal = try decoder.decode(MealPrepDTO.self, from: Data(json.utf8))
        #expect(meal.basis == .total)
        #expect(meal.perPortion.calories == 600)
        #expect(meal.total.calories == 2400)
        #expect(meal.hasPhoto)
        #expect(meal.ingredients[0].line == "1 kg Chicken breast")
        // No quantity means the name stands alone, with no stray space.
        #expect(meal.ingredients[1].line == "Broccoli")
    }

    @Test func decodesMealPrepWithNoMacrosOrPhoto() throws {
        let json = """
        {"id":"m2","name":"Overnight oats","description":null,"instructions":null,
         "prepMinutes":null,"portions":1,"basis":"portion",
         "perPortion":{"calories":null,"proteinG":null,"carbsG":null,"fatG":null},
         "total":{"calories":null,"proteinG":null,"carbsG":null,"fatG":null},
         "photoUrl":null,"hasPhoto":false,"ingredients":[],"sortOrder":0,
         "createdAt":"2026-08-18T11:00:00.000Z","updatedAt":"2026-08-18T11:00:00.000Z"}
        """
        let meal = try decoder.decode(MealPrepDTO.self, from: Data(json.utf8))
        #expect(meal.perPortion.isEmpty)
        #expect(meal.hasPhoto == false)
        #expect(meal.ingredients.isEmpty)
    }
}
