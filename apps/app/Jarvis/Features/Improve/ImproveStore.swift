import Foundation
import JarvisAPI
import Observation

/// Feature store for improvement areas: the area list with due state, per-area
/// check-in timelines, photo uploads, and area CRUD.
@Observable
@MainActor
final class ImproveStore {
    private(set) var areas: LoadState<ImprovementAreaListResponse> = .idle
    /// Check-in timelines by area id (loaded on detail open, newest first).
    private(set) var checkins: [String: [AreaCheckinDTO]] = [:]
    private(set) var uploadingAreaIds: Set<String> = []
    var mutationError: String?

    private var model: AppModel?

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    var response: ImprovementAreaListResponse? { areas.value }
    var dueAreas: [ImprovementAreaDTO] { response?.areas.filter(\.dueThisWeek) ?? [] }

    // MARK: - Loading

    func load() async {
        guard let model else { return }
        do {
            areas = .loaded(try await model.api.improvementAreas())
        } catch {
            model.handle(error)
            if areas.value == nil { areas = .failed(TodayStore.message(for: error)) }
        }
    }

    func loadCheckins(areaId: String) async {
        guard let model else { return }
        do {
            checkins[areaId] = try await model.api.areaCheckins(areaId: areaId).checkins
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
        }
    }

    // MARK: - Check-ins

    /// Downscales and uploads a photo check-in for today. Returns success.
    @discardableResult
    func uploadCheckin(areaId: String, imageData: Data) async -> Bool {
        guard let model, !uploadingAreaIds.contains(areaId) else { return false }
        guard let jpeg = ImageDownscaler.jpegData(from: imageData) else {
            mutationError = "That image could not be read — try a different photo."
            return false
        }
        uploadingAreaIds.insert(areaId)
        defer { uploadingAreaIds.remove(areaId) }
        do {
            let checkin = try await model.api.uploadCheckin(
                areaId: areaId,
                dayKey: DayKeyMath.todayKey(),
                data: jpeg,
                contentType: "image/jpeg",
            )
            var timeline = checkins[areaId] ?? []
            timeline.removeAll { $0.weekKey == checkin.weekKey }
            timeline.insert(checkin, at: 0)
            checkins[areaId] = timeline
            await load() // refresh due state
            return true
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
            return false
        }
    }

    // MARK: - Area CRUD

    @discardableResult
    func createArea(name: String, emoji: String?, betterLooksLike: String?) async -> Bool {
        guard let model else { return false }
        do {
            _ = try await model.api.createImprovementArea(ImprovementAreaCreateRequest(
                name: name,
                emoji: emoji,
                betterLooksLike: betterLooksLike,
            ))
            await load()
            return true
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
            return false
        }
    }

    @discardableResult
    func updateArea(id: String, name: String, emoji: String?, betterLooksLike: String?) async -> Bool {
        guard let model else { return false }
        do {
            _ = try await model.api.patchImprovementArea(id: id, [
                "name": .string(name),
                "emoji": emoji.map(JSONValue.string) ?? .null,
                "betterLooksLike": betterLooksLike.map(JSONValue.string) ?? .null,
            ])
            await load()
            return true
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
            return false
        }
    }

    func archiveArea(id: String) async {
        guard let model else { return }
        do {
            _ = try await model.api.patchImprovementArea(id: id, ["archived": .bool(true)])
            await load()
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
        }
    }

    func deleteArea(id: String) async {
        guard let model else { return }
        do {
            _ = try await model.api.deleteImprovementArea(id: id)
            checkins[id] = nil
            await load()
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
        }
    }
}
