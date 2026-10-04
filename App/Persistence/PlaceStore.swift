import CoreLocation
import Foundation
import SwiftData

@MainActor
final class PlaceStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all() -> [PlaceEntity] {
        (try? context.fetch(FetchDescriptor<PlaceEntity>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func match(_ spoken: String) -> PlaceEntity? {
        let places = all()
        let target = spoken.lowercased()
        return places.first { place in
            ([place.name] + place.aliases).contains { $0.lowercased() == target }
        } ?? places.first { $0.matches(spoken) }
    }

    func place(containing location: CLLocation) -> PlaceEntity? {
        all()
            .map { place in (place, location.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))) }
            .filter { $0.1 <= max($0.0.radius, location.horizontalAccuracy) }
            .min { $0.1 < $1.1 }?
            .0
    }

    @discardableResult
    func add(name: String, alias: String?, coordinate: CLLocationCoordinate2D, radius: Double = 150) throws -> PlaceEntity {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlias = alias?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases = [cleanAlias].compactMap { $0 }.filter { !$0.isEmpty && $0 != cleanName.lowercased() }
        let place = PlaceEntity(name: cleanName, aliases: aliases, latitude: coordinate.latitude, longitude: coordinate.longitude, radius: radius)
        context.insert(place)
        try context.save()
        return place
    }

    func delete(_ place: PlaceEntity) throws {
        context.delete(place)
        try context.save()
    }

    func deleteAll() throws {
        try context.delete(model: PlaceEntity.self)
        try context.save()
    }
}
