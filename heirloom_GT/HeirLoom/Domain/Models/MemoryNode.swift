import Foundation

struct MemoryNode: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    var authorID: UUID
    var timestamp: Date
    var rawTranscript: String
    var narrativeSummary: String
    var extractedEra: String
    var location: String?
    var entitiesMentioned: [String]
    var hobbiesIdentified: [String]
    var tags: [String]
    var mediaURLs: [URL]

    init(
        id: UUID = UUID(),
        authorID: UUID,
        timestamp: Date = .now,
        rawTranscript: String,
        narrativeSummary: String,
        extractedEra: String,
        location: String? = nil,
        entitiesMentioned: [String] = [],
        hobbiesIdentified: [String] = [],
        tags: [String] = [],
        mediaURLs: [URL] = []
    ) {
        self.id = id
        self.authorID = authorID
        self.timestamp = timestamp
        self.rawTranscript = rawTranscript
        self.narrativeSummary = narrativeSummary
        self.extractedEra = extractedEra
        self.location = location
        self.entitiesMentioned = entitiesMentioned
        self.hobbiesIdentified = hobbiesIdentified
        self.tags = tags
        self.mediaURLs = mediaURLs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case timestamp
        case rawTranscript = "raw_transcript"
        case narrativeSummary = "narrative_summary"
        case extractedEra = "extracted_era"
        case location
        case entitiesMentioned = "entities_mentioned"
        case hobbiesIdentified = "hobbies_identified"
        case tags
        case mediaURLs = "media_urls"
    }
}
