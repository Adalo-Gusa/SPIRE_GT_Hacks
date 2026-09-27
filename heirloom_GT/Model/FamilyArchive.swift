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
    @Published private(set) var feedPosts: [FeedPostDocument] = []
    @Published private(set) var places: [FamilyPlace] = []
    @Published private(set) var sparks: [SparkDocument] = []

    /// Loomie's story extraction and saving (Backboard, Atlas, and a local copy on the phone).
    let voiceModel = LoomVoiceViewModel()

    private var coordinateCache: [String: CLLocationCoordinate2D?] = [:]
    private var notifiedSparkIds: Set<String> = []
    private var isRefreshing = false

    /// Reloads members, stories, feed posts and places.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let service = MongoDBAtlasService.shared
        members = (try? await service.fetchFamilyMembers()) ?? members

        // Stories saved on this phone are included too, so a story shows up even if Atlas couldn't be reached.
        // Ones the server has come back with its author; any it doesn't have were told on this phone.
        let remote = (try? await service.fetchStories()) ?? []
        let local = voiceModel.savedArtifacts.map {
            StoryDocument(artifact: $0, familyId: AppConfiguration.mongoDBFamilyId, authorId: CurrentUser.memberId)
        }
        var seen = Set<String>()
        stories = (remote + local)
            .filter { seen.insert($0._id).inserted }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        // Family Feed social moments & Instagram updates
        feedPosts = (try? await service.fetchFeedPosts()) ?? feedPosts

        // Intergenerational Connection Sparks from the Archiving Agent
        let remoteSparks = (try? await service.fetchSparks()) ?? []
        sparks = remoteSparks

        // Notify user about newly discovered sparks
        for spark in remoteSparks where !spark.isRead && !notifiedSparkIds.contains(spark._id) {
            notifiedSparkIds.insert(spark._id)
            let elder = members.first(where: { $0._id == spark.elderId })?.name ?? "Grandpa Joe"
            let target = members.first(where: { $0._id == spark.targetMemberId })?.name ?? "Alex"
            LoomNotificationManager.shared.scheduleSparkNotification(spark, elderName: elder, targetName: target)
        }

        places = await placesForStories(stories)
    }

    /// Adds a new post to the Family Feed (from in-app composer or Share Extension).
    func addFeedPost(_ post: FeedPostDocument) async throws {
        feedPosts.insert(post, at: 0)
        try await MongoDBAtlasService.shared.insertFeedPost(post)
    }

    // MARK: - Member Updates & Badges (Home Corkboard)

    /// Returns all recent updates (posts and stories) for a specific member, newest first.
    func updates(for memberId: String) -> [MemberUpdateItem] {
        var items: [MemberUpdateItem] = []

        // 1. Posts by this member
        let memberPosts = feedPosts.filter { $0.authorId == memberId }
        for post in memberPosts {
            let srcLabel = post.source == "instagram" ? "📸 Instagram Update" : "💬 Family Moment"
            items.append(MemberUpdateItem(
                id: post.id,
                title: srcLabel,
                subtitle: post.content,
                date: post.createdAt,
                type: .post(post),
                isUnread: post.isUnread
            ))
        }

        // 2. Stories by this member
        let memberStories = stories.filter { $0.authorId == memberId }
        for story in memberStories {
            items.append(MemberUpdateItem(
                id: story.id,
                title: "📖 \(story.title)",
                subtitle: story.narrativeSummary,
                date: story.createdAt ?? .distantPast,
                type: .story(story),
                isUnread: false
            ))
        }

        return items.sorted { $0.date > $1.date }
    }

    /// Returns how many unread updates a member has. Your own posts never count as unread.
    func unreadCount(for memberId: String) -> Int {
        guard memberId != CurrentUser.memberId else { return 0 }
        return feedPosts.filter { $0.authorId == memberId && $0.isUnread }.count
    }

    /// Checks if a member has unread notifications.
    func hasUnreadUpdates(memberId: String) -> Bool {
        unreadCount(for: memberId) > 0
    }

    /// Marks all posts for a member as read.
    func markUpdatesRead(for memberId: String) {
        for idx in feedPosts.indices {
            if feedPosts[idx].authorId == memberId {
                feedPosts[idx].isUnread = false
            }
        }
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

// MARK: - Member Update Item

enum MemberUpdateType: Equatable {
    case post(FeedPostDocument)
    case story(StoryDocument)
}

struct MemberUpdateItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let date: Date
    let type: MemberUpdateType
    var isUnread: Bool
}
