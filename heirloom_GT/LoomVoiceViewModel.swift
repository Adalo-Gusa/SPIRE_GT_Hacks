import Foundation

struct ConversationTurn: Equatable {
    let sender: String
    let text: String
}

@MainActor
final class LoomVoiceViewModel: ObservableObject {
    @Published private(set) var savedArtifacts: [StoryArtifact] = []
    @Published private(set) var threadId = UUID().uuidString

    private static let storageKey = "loomie.savedStoryArtifacts"

    init() {
        savedArtifacts = Self.load()
    }

    func finishAndSaveConversation(turns: [ConversationTurn]) async throws -> StoryArtifact {
        let transcript = Self.transcript(from: turns)
        guard !transcript.isEmpty else {
            throw LoomError.decoding("The conversation has no story to save.")
        }
        print("[Loomie] wrap-up transcript chars=\(transcript.count) thread=\(threadId)")
        let artifact = try await LoomService.shared.extractStoryArtifact(from: transcript)
        
        // Guarantee local persistence immediately
        savedArtifacts.insert(artifact, at: 0)
        persist()
        beginNewThread()

        // Sync to Backboard permanent memories
        do {
            try await LoomService.shared.commitPermanentMemory(
                assistantId: AppConfiguration.defaultAssistantId,
                factSummary: artifact.permanentFactSummary
            )
            print("[Loomie] saved story “\(artifact.title)” and committed to Backboard for thread \(threadId)")
        } catch {
            print("[Loomie] warning: permanent memory sync failed: \(error.localizedDescription); local copy preserved")
        }

        // Save to the MongoDB Atlas 'stories' collection, then add any new passions to the teller's profile.
        // The teller is whoever is using this phone. Each step reports its own result so a failure isn't hidden
        // behind a success message.
        let tellerId = CurrentUser.memberId
        let storyDoc = StoryDocument(artifact: artifact, familyId: AppConfiguration.mongoDBFamilyId, authorId: tellerId)
        do {
            try await MongoDBAtlasService.shared.insertStory(storyDoc)
            print("[Loomie] saved story to MongoDB Atlas 'stories' collection")
        } catch {
            print("[Loomie] warning: couldn't save story to MongoDB Atlas (\(error.localizedDescription)); kept a local copy. Is heirloom-api running at \(AppConfiguration.heirloomAPIBaseURL.absoluteString)?")
        }
        if !artifact.passionsOrHobbies.isEmpty {
            do {
                try await MongoDBAtlasService.shared.appendPassionsToMember(
                    memberId: tellerId,
                    newPassions: artifact.passionsOrHobbies
                )
            } catch {
                print("[Loomie] warning: couldn't update member passions in MongoDB Atlas (\(error.localizedDescription))")
            }
        }

        return artifact
    }

    func beginNewThread() {
        threadId = UUID().uuidString
        print("[Loomie] new conversation thread \(threadId)")
    }

    static func transcript(from turns: [ConversationTurn]) -> String {
        turns.compactMap { turn in
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != "…" else { return nil }
            switch turn.sender {
            case "You":
                return "Elder: \(text)"
            case "Loomie":
                return "Loomie: \(text)"
            default:
                return nil
            }
        }.joined(separator: "\n")
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(savedArtifacts) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func load() -> [StoryArtifact] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([StoryArtifact].self, from: data)) ?? []
    }
}
