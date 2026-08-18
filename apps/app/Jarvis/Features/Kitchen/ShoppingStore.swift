import Foundation
import JarvisAPI
import Observation

/// The shopping list. Every write here is optimistic and queued: the whole
/// point of the feature is standing in a shop, and shop basements have no
/// signal. Nothing on this screen ever waits for the network.
@Observable
@MainActor
final class ShoppingStore {
    private(set) var state: LoadState<[ShoppingItemDTO]> = .idle
    var actionError: String?

    private var model: AppModel?

    func bind(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    var items: [ShoppingItemDTO] { state.value ?? [] }

    /// Still to buy, in the order they were added.
    var remaining: [ShoppingItemDTO] {
        items.filter { !$0.checked }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Already in the trolley. Newest first — the last thing you ticked is the
    /// one you are most likely to have ticked by mistake.
    var picked: [ShoppingItemDTO] {
        items.filter(\.checked).sorted { ($0.checkedAt ?? "") > ($1.checkedAt ?? "") }
    }

    var isEmpty: Bool { items.isEmpty }

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
        if !force, let cached = model.store.read([ShoppingItemDTO].self, .shoppingList) {
            state = .loaded(cached.value)
            if cached.isFresh { return }
        }
        if state.value == nil { state = .loading }

        let ticket = model.writeTicket
        do {
            let response = try await model.api.shoppingItems()
            // A tap that landed while this was in flight is newer than the
            // response; keeping the response would visibly un-tick the row.
            guard !model.hasWritten(since: ticket) else { return }
            state = .loaded(response.items)
            model.store.write(response.items, .shoppingList)
        } catch {
            model.handle(error)
            if state.value == nil { state = .failed(TodayStore.message(for: error)) }
        }
    }

    // MARK: - Writes

    /// Adds one item. The row appears instantly; the request is queued.
    func add(_ text: String) {
        guard let model else { return }
        let parsed = ShoppingLineParser.parse(text)
        guard let parsed else { return }

        let id = UUID().uuidString
        let item = ShoppingItemDTO(
            id: id,
            name: parsed.name,
            quantity: parsed.quantity,
            sortOrder: (items.map(\.sortOrder).max() ?? 0) + 1,
            createdAt: ISO8601DateFormatter().string(from: .now),
        )
        apply(items + [item])
        model.mutate(
            "POST",
            "/shopping-items",
            body: ShoppingItemCreateRequest(id: id, name: parsed.name, quantity: parsed.quantity),
            entities: [.shopping],
            label: parsed.name,
        )
    }

    func setChecked(_ item: ShoppingItemDTO, _ checked: Bool) {
        guard let model else { return }
        apply(items.map { $0.id == item.id ? $0.toggled(checked) : $0 })
        // Absolute, never a toggle: a replayed request must not flip it back.
        model.mutate(
            "PATCH",
            "/shopping-items/\(item.id)",
            body: ["checked": JSONValue.bool(checked)] as JSONObject,
            entities: [.shopping],
            label: item.name,
        )
    }

    func rename(_ item: ShoppingItemDTO, name: String, quantity: String?) {
        guard let model else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cleanQuantity = quantity?.trimmingCharacters(in: .whitespacesAndNewlines)
        apply(items.map { row in
            guard row.id == item.id else { return row }
            return ShoppingItemDTO(
                id: row.id,
                name: trimmed,
                quantity: (cleanQuantity?.isEmpty ?? true) ? nil : cleanQuantity,
                checked: row.checked,
                checkedAt: row.checkedAt,
                sortOrder: row.sortOrder,
                createdAt: row.createdAt,
            )
        })
        model.mutate(
            "PATCH",
            "/shopping-items/\(item.id)",
            body: [
                "name": JSONValue.string(trimmed),
                "quantity": (cleanQuantity?.isEmpty ?? true)
                    ? JSONValue.null : JSONValue.string(cleanQuantity!),
            ] as JSONObject,
            entities: [.shopping],
            label: trimmed,
        )
    }

    func delete(_ item: ShoppingItemDTO) {
        guard let model else { return }
        apply(items.filter { $0.id != item.id })
        model.mutate(
            "DELETE",
            "/shopping-items/\(item.id)",
            entities: [.shopping],
            label: item.name,
        )
    }

    /// Clears everything already ticked off — the end-of-shop tidy.
    func clearPicked() {
        guard let model else { return }
        guard !picked.isEmpty else { return }
        apply(items.filter { !$0.checked })
        model.mutate(
            "POST",
            "/shopping-items/clear",
            body: ["scope": JSONValue.string("checked")] as JSONObject,
            entities: [.shopping],
            label: "picked-up items",
        )
    }

    func clearAll() {
        guard let model else { return }
        guard !items.isEmpty else { return }
        apply([])
        model.mutate(
            "POST",
            "/shopping-items/clear",
            body: ["scope": JSONValue.string("all")] as JSONObject,
            entities: [.shopping],
            label: "the shopping list",
        )
    }

    /// Puts a meal prep's ingredients on the list. Goes straight to the server
    /// (rather than through the outbox) because the response tells us how many
    /// were skipped as already-there, which is what the confirmation says.
    @discardableResult
    func addIngredients(_ ingredients: [MealIngredientDTO]) async -> (added: Int, skipped: Int)? {
        guard let model, !ingredients.isEmpty else { return nil }
        let request = ShoppingBulkAddRequest(
            items: ingredients.map {
                ShoppingBulkAddRequest.Item(name: $0.name, quantity: $0.quantity)
            },
        )
        do {
            let response = try await model.api.addShoppingItems(request)
            apply(response.items)
            model.invalidate([.shopping])
            return (response.added, response.skipped)
        } catch {
            model.handle(error)
            actionError = TodayStore.message(for: error)
            return nil
        }
    }

    /// Writes local state through to the cache so a relaunch keeps the edit.
    private func apply(_ next: [ShoppingItemDTO]) {
        state = .loaded(next)
        model?.store.write(next, .shoppingList)
    }
}

/// Splits "2 kg chicken" into a quantity and a name.
///
/// One text field is the whole reason this feature is faster than Notes, so
/// the parser has to be predictable rather than clever: it only splits when
/// the line *starts* with a number, and it only absorbs a following word when
/// that word is a unit it recognises. "3 lemons" keeps "lemons" as the name;
/// "2 kg chicken" does not end up as an item called "kg chicken".
enum ShoppingLineParser {
    struct Result: Equatable {
        var name: String
        var quantity: String?
    }

    private static let units: Set<String> = [
        "g", "gr", "kg", "mg", "ml", "cl", "dl", "l", "lt",
        "x", "pcs", "pack", "packs", "bottle", "bottles", "can", "cans",
        "box", "boxes", "bag", "bags", "tin", "tins", "jar", "jars",
    ]

    static func parse(_ raw: String) -> Result? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 2, isNumeric(tokens[0]) else {
            return Result(name: trimmed, quantity: nil)
        }

        var quantity = tokens.removeFirst()
        // "500 g rice" — take the unit too, but only if something is left to
        // name the item with.
        if tokens.count >= 2, units.contains(tokens[0].lowercased()) {
            quantity += " \(tokens.removeFirst())"
        }
        let name = tokens.joined(separator: " ")
        guard !name.isEmpty else { return Result(name: trimmed, quantity: nil) }
        return Result(name: name, quantity: quantity)
    }

    /// "2", "2.5", "1,5" and "2x" all count; "2nd" does not.
    private static func isNumeric(_ token: String) -> Bool {
        var value = token.lowercased()
        if value.hasSuffix("x") { value.removeLast() }
        guard !value.isEmpty else { return false }
        return value.allSatisfy { $0.isNumber || $0 == "." || $0 == "," }
            && value.contains(where: \.isNumber)
    }
}
