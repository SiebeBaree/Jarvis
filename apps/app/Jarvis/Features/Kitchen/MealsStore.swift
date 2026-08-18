import Foundation
import JarvisAPI
import Observation

/// Meal preps: the user's own cookbook.
///
/// Unlike the shopping list this is not an offline-first surface — a meal prep
/// is written once at a keyboard, not tapped at speed, and it can carry a
/// photo, which the outbox has no way to replay. So writes here are awaited
/// and report their own errors.
@Observable
@MainActor
final class MealsStore {
    private(set) var state: LoadState<[MealPrepDTO]> = .idle
    var actionError: String?
    /// Set after a successful "add ingredients to the shopping list", so the
    /// detail screen can confirm what actually happened.
    var shoppingConfirmation: String?

    private var model: AppModel?

    func bind(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    var meals: [MealPrepDTO] { state.value ?? [] }

    func meal(withId id: String) -> MealPrepDTO? {
        meals.first { $0.id == id }
    }

    // MARK: - Loading

    private var inFlight: Task<Void, Never>?

    func load(force: Bool = false) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await performLoad(force: force) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performLoad(force: Bool) async {
        guard let model else { return }
        if !force, let cached = model.store.read([MealPrepDTO].self, .mealPreps) {
            state = .loaded(cached.value)
            // Photo URLs are presigned and expire after an hour, so a cached
            // list is only good for text. Always revalidate on a cold read
            // that carries photos.
            if cached.isFresh, !cached.value.contains(where: \.hasPhoto) { return }
        }
        if state.value == nil { state = .loading }
        do {
            let response = try await model.api.mealPreps()
            state = .loaded(response.mealPreps)
            model.store.write(response.mealPreps, .mealPreps)
        } catch {
            model.handle(error)
            if state.value == nil { state = .failed(TodayStore.message(for: error)) }
        }
    }

    // MARK: - Writes

    /// Creates a meal prep and, when one was picked, uploads its photo.
    /// Returns the saved meal so the editor can dismiss onto its detail.
    func create(_ request: MealPrepRequest, photo: Data?) async -> MealPrepDTO? {
        guard let model else { return nil }
        do {
            var meal = try await model.api.createMealPrep(request)
            if let photo {
                meal = try await uploadPhoto(mealId: meal.id, data: photo)
            }
            await load(force: true)
            model.invalidate([.meal])
            return meal
        } catch {
            model.handle(error)
            actionError = TodayStore.message(for: error)
            return nil
        }
    }

    func update(id: String, _ request: MealPrepRequest, photo: Data?) async -> MealPrepDTO? {
        guard let model else { return nil }
        do {
            var meal = try await model.api.patchMealPrep(id: id, request)
            if let photo {
                meal = try await uploadPhoto(mealId: id, data: photo)
            }
            await load(force: true)
            model.invalidate([.meal])
            return meal
        } catch {
            model.handle(error)
            actionError = TodayStore.message(for: error)
            return nil
        }
    }

    private func uploadPhoto(mealId: String, data: Data) async throws -> MealPrepDTO {
        guard let model else { throw APIClientError.network(underlying: "not configured") }
        guard let jpeg = ImageDownscaler.jpegData(from: data) else {
            throw APIClientError.decoding(underlying: "unreadable image")
        }
        return try await model.api.uploadMealPhoto(id: mealId, data: jpeg, contentType: "image/jpeg")
    }

    func removePhoto(id: String) async {
        guard let model else { return }
        do {
            _ = try await model.api.deleteMealPhoto(id: id)
            await load(force: true)
            model.invalidate([.meal])
        } catch {
            model.handle(error)
            actionError = TodayStore.message(for: error)
        }
    }

    func delete(id: String) async -> Bool {
        guard let model else { return false }
        do {
            _ = try await model.api.deleteMealPrep(id: id)
            state = .loaded(meals.filter { $0.id != id })
            model.store.write(meals, .mealPreps)
            model.invalidate([.meal])
            return true
        } catch {
            model.handle(error)
            actionError = TodayStore.message(for: error)
            return false
        }
    }

    /// "Put everything I need for this on the shopping list."
    func sendToShoppingList(_ meal: MealPrepDTO, shopping: ShoppingStore) async {
        guard !meal.ingredients.isEmpty else { return }
        guard let result = await shopping.addIngredients(meal.ingredients) else {
            actionError = shopping.actionError ?? "Could not reach the shopping list."
            return
        }
        shoppingConfirmation = Self.confirmation(added: result.added, skipped: result.skipped)
    }

    /// Says what happened rather than just "done" — "nothing added" is a real
    /// outcome when everything is already on the list, and silence would read
    /// as a bug.
    static func confirmation(added: Int, skipped: Int) -> String {
        switch (added, skipped) {
        case (0, _):
            "Everything was already on your list"
        case (let added, 0):
            "Added \(added) item\(added == 1 ? "" : "s") to your shopping list"
        case (let added, let skipped):
            "Added \(added), skipped \(skipped) already on the list"
        }
    }
}
