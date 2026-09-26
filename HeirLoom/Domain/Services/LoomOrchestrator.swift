import Foundation

/// Coordinates cross-app ingestion from the Share Extension (Instagram posts)
/// into the Family Feed, MongoDB Atlas, and Backboard.io memory.
@MainActor
public final class LoomOrchestrator: ObservableObject {
    public static let shared = LoomOrchestrator()

    @Published public private(set) var isProcessing: Bool = false
    @Published public private(set) var lastIngestedPostTitle: String? = nil

    private init() {}

    /// Checks the App Group queue for posts shared from Instagram and imports them into Family Feed.
    public func processPendingSharedPosts(archive: FamilyArchive) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let pending = AppGroupStorage.shared.fetchPendingPosts()
        guard !pending.isEmpty else { return }

        print("[LoomOrchestrator] Found \(pending.count) pending shared post(s) to ingest.")

        for post in pending {
            do {
                // 1. Analyze caption with Grok to extract location and passions
                var extractedPassions: [String] = []
                var extractedLocation: String? = nil

                let promptText = "Instagram caption by \(post.authorName): \"\(post.caption)\""
                if let artifact = try? await LoomService.shared.extractStoryArtifact(from: promptText) {
                    extractedPassions = artifact.passionsOrHobbies
                    extractedLocation = artifact.location
                }

                // 2. Locate author details from family archive
                let member = archive.members.first { $0._id == post.authorId }
                let authorAvatar = member?.avatarUrl

                // 3. Build FeedPostDocument
                let feedPost = FeedPostDocument(
                    id: post.id,
                    familyId: AppConfiguration.mongoDBFamilyId,
                    authorId: post.authorId,
                    authorName: post.authorName,
                    authorAvatarUrl: authorAvatar,
                    content: post.caption,
                    imageUrl: post.imageFileName,
                    postUrl: post.postURL,
                    source: post.source,
                    passions: extractedPassions,
                    location: extractedLocation,
                    createdAt: post.timestamp,
                    isUnread: true
                )

                // 4. Save to Family Feed & MongoDB Atlas
                try await archive.addFeedPost(feedPost)
                print("[LoomOrchestrator] Successfully ingested post '\(post.id)' into Family Feed.")

                // 5. Enrich member passions in MongoDB Atlas if any were detected
                if !extractedPassions.isEmpty {
                    try? await MongoDBAtlasService.shared.appendPassionsToMember(
                        memberId: post.authorId,
                        newPassions: extractedPassions
                    )
                }

                // 6. Commit biographical memory to Backboard.io so Loomie can converse about it
                let fact = "Recent social post by \(post.authorName): \"\(post.caption)\". Passions: \(extractedPassions.joined(separator: ", "))."
                try? await LoomService.shared.commitPermanentMemory(
                    assistantId: AppConfiguration.defaultAssistantId,
                    factSummary: fact
                )

                // 7. Remove from pending queue
                AppGroupStorage.shared.markPostCompleted(id: post.id)
                lastIngestedPostTitle = post.caption
            } catch {
                print("[LoomOrchestrator] Ingestion failed for post '\(post.id)': \(error.localizedDescription)")
            }
        }

        // 8. Refresh Family Archive
        await archive.refresh()
    }
}
