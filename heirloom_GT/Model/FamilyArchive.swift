import Foundation
import CoreLocation

/// The family's shared data for every screen: members for the Home tree, stories for the Family Notebook,
/// and story places for the map. Loads from MongoDB Atlas through `MongoDBAtlasService`, which falls back to
/// the built-in Clarke family when the server can't be reached.
@MainActor
final class FamilyArchive: ObservableObject {
    @Published private(set) var members: [MemberDocument] = []
    /// Newest first.
    @Published private(set) var stories: [StoryDocument] = []
    @Published private(set) var places: [FamilyPlace] = []

    /// Loomie's story extraction and saving (Backboard, Atlas, and a local copy on the phone).
    let voiceModel = LoomVoiceViewModel()

    private var coordinateCache: [String: CLLocationCoordinate2D?] = [:]
    private var isRefreshing = false

    /// Reloads members, stories and places.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let service = MongoDBAtlasService.shared
        members = (try? await service.fetchFamilyMembers()) ?? members

        // Stories saved on this phone are included too, so a story shows up even if Atlas couldn't be reached.
        let remote = (try? await service.fetchStories()) ?? []
        let local = voiceModel.savedArtifacts.map {
            StoryDocument(artifact: $0, familyId: AppConfiguration.mongoDBFamilyId, authorId: "member_grandpa_joe")
        }
        var seen = Set<String>()
        stories = (local + remote)
            .filter { seen.insert($0._id).inserted }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        places = await placesForStories(stories)
    }

    /// One map pin per story whose location Apple's geocoder can find.
    private func placesForStories(_ stories: [StoryDocument]) async -> [FamilyPlace] {
        var result: [FamilyPlace] = []
        for story in stories {
            guard let location = story.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !location.isEmpty,
                  let coordinate = await coordinate(for: location)
            else { continue }
            result.append(FamilyPlace(
                id: story._id,
                name: location,
                detail: story.title,
                coordinate: coordinate))
        }
        return result
    }

    private func coordinate(for location: String) async -> CLLocationCoordinate2D? {
        if let cached = coordinateCache[location] { return cached }
        let coordinate = try? await CLGeocoder().geocodeAddressString(location).first?.location?.coordinate
        coordinateCache[location] = coordinate
        return coordinate
    }
}
