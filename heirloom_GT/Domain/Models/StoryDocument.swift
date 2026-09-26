import Foundation

/// Represents an oral family story artifact captured through Loomie,
/// mapped 1:1 with the MongoDB Atlas `stories` collection.
struct StoryDocument: Identifiable, Codable, Equatable, Sendable {
    var id: String { _id }
    var _id: String
    var familyId: String
    var authorId: String
    var title: String
    var narrativeSummary: String
    var extractedEra: String?
    var location: String?
    var goldenQuote: String?
    var emotionalTone: String?
    var generationBridge: String?
    var passions: [String]
    var peopleMentioned: [String]
    var grokImaginePrompt: String?
    var rawTranscript: String?
    var imageUrl: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case _id
        case id
        case familyId = "family_id"
        case altFamilyId = "familyId"
        case authorId = "author_id"
        case altAuthorId = "authorId"
        case title
        case narrativeSummary = "narrative_summary"
        case altNarrativeSummary = "narrativeSummary"
        case extractedEra = "extracted_era"
        case altExtractedEra = "extractedEra"
        case location
        case goldenQuote = "golden_quote"
        case altGoldenQuote = "goldenQuote"
        case emotionalTone = "emotional_tone"
        case altEmotionalTone = "emotionalTone"
        case generationBridge = "generation_bridge"
        case altGenerationBridge = "generationBridge"
        case passions
        case peopleMentioned = "people_mentioned"
        case altPeopleMentioned = "peopleMentioned"
        case grokImaginePrompt = "grok_imagine_prompt"
        case altGrokImaginePrompt = "grokImaginePrompt"
        case rawTranscript = "raw_transcript"
        case altRawTranscript = "rawTranscript"
        case imageUrl = "image_url"
        case altImageUrl = "imageUrl"
        case createdAt = "created_at"
        case altCreatedAt = "createdAt"
        case updatedAt = "updated_at"
        case altUpdatedAt = "updatedAt"
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        authorId: String,
        title: String,
        narrativeSummary: String,
        extractedEra: String? = nil,
        location: String? = nil,
        goldenQuote: String? = nil,
        emotionalTone: String? = nil,
        generationBridge: String? = nil,
        passions: [String] = [],
        peopleMentioned: [String] = [],
        grokImaginePrompt: String? = nil,
        rawTranscript: String? = nil,
        imageUrl: String? = nil,
        createdAt: Date? = Date(),
        updatedAt: Date? = Date()
    ) {
        self._id = id
        self.familyId = familyId
        self.authorId = authorId
        self.title = title
        self.narrativeSummary = narrativeSummary
        self.extractedEra = extractedEra
        self.location = location
        self.goldenQuote = goldenQuote
        self.emotionalTone = emotionalTone
        self.generationBridge = generationBridge
        self.passions = passions
        self.peopleMentioned = peopleMentioned
        self.grokImaginePrompt = grokImaginePrompt
        self.rawTranscript = rawTranscript
        self.imageUrl = imageUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Convenience initializer bridging from a live Loomie StoryArtifact
    init(artifact: StoryArtifact, familyId: String = "fam_clarke_001", authorId: String = "member_grandpa_joe") {
        self._id = artifact.id
        self.familyId = familyId
        self.authorId = authorId
        self.title = artifact.title
        self.narrativeSummary = artifact.narrativeSummary
        self.extractedEra = artifact.extractedEra
        self.location = artifact.location
        self.goldenQuote = artifact.goldenQuote
        self.emotionalTone = artifact.emotionalTone
        self.generationBridge = artifact.generationBridge
        self.passions = artifact.passionsOrHobbies
        self.peopleMentioned = artifact.peopleMentioned
        self.grokImaginePrompt = artifact.grokImaginePrompt
        self.rawTranscript = artifact.rawTranscript
        self.imageUrl = nil
        self.createdAt = artifact.createdAt
        self.updatedAt = Date()
    }

    /// Converts this MongoDB document back into a local StoryArtifact
    func toStoryArtifact() -> StoryArtifact {
        StoryArtifact(
            id: _id,
            title: title,
            narrativeSummary: narrativeSummary,
            extractedEra: extractedEra,
            location: location,
            peopleMentioned: peopleMentioned,
            passionsOrHobbies: passions,
            goldenQuote: goldenQuote,
            emotionalTone: emotionalTone,
            generationBridge: generationBridge,
            grokImaginePrompt: grokImaginePrompt ?? "",
            rawTranscript: rawTranscript ?? "",
            createdAt: createdAt ?? Date()
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let primaryId = try? container.decode(String.self, forKey: ._id)
        let altId = try? container.decode(String.self, forKey: .id)
        self._id = primaryId ?? altId ?? UUID().uuidString

        let fam = try? container.decode(String.self, forKey: .familyId)
        let altFam = try? container.decode(String.self, forKey: .altFamilyId)
        self.familyId = fam ?? altFam ?? "fam_clarke_001"

        let auth = try? container.decode(String.self, forKey: .authorId)
        let altAuth = try? container.decode(String.self, forKey: .altAuthorId)
        self.authorId = auth ?? altAuth ?? "unknown_member"

        self.title = try container.decode(String.self, forKey: .title)

        let ns = try? container.decode(String.self, forKey: .narrativeSummary)
        let altNs = try? container.decode(String.self, forKey: .altNarrativeSummary)
        self.narrativeSummary = ns ?? altNs ?? ""

        self.extractedEra = (try? container.decode(String.self, forKey: .extractedEra))
            ?? (try? container.decode(String.self, forKey: .altExtractedEra))

        self.location = (try? container.decode(String.self, forKey: .location))

        self.goldenQuote = (try? container.decode(String.self, forKey: .goldenQuote))
            ?? (try? container.decode(String.self, forKey: .altGoldenQuote))

        self.emotionalTone = (try? container.decode(String.self, forKey: .emotionalTone))
            ?? (try? container.decode(String.self, forKey: .altEmotionalTone))

        self.generationBridge = (try? container.decode(String.self, forKey: .generationBridge))
            ?? (try? container.decode(String.self, forKey: .altGenerationBridge))

        self.passions = (try? container.decode([String].self, forKey: .passions)) ?? []
        self.peopleMentioned = (try? container.decode([String].self, forKey: .peopleMentioned))
            ?? (try? container.decode([String].self, forKey: .altPeopleMentioned)) ?? []

        self.grokImaginePrompt = (try? container.decode(String.self, forKey: .grokImaginePrompt))
            ?? (try? container.decode(String.self, forKey: .altGrokImaginePrompt))

        self.rawTranscript = (try? container.decode(String.self, forKey: .rawTranscript))
            ?? (try? container.decode(String.self, forKey: .altRawTranscript))

        self.imageUrl = (try? container.decode(String.self, forKey: .imageUrl))
            ?? (try? container.decode(String.self, forKey: .altImageUrl))

        self.createdAt = (try? container.decode(Date.self, forKey: .createdAt))
            ?? (try? container.decode(Date.self, forKey: .altCreatedAt))

        self.updatedAt = (try? container.decode(Date.self, forKey: .updatedAt))
            ?? (try? container.decode(Date.self, forKey: .altUpdatedAt))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_id, forKey: ._id)
        try container.encode(familyId, forKey: .familyId)
        try container.encode(authorId, forKey: .authorId)
        try container.encode(title, forKey: .title)
        try container.encode(narrativeSummary, forKey: .narrativeSummary)
        try container.encodeIfPresent(extractedEra, forKey: .extractedEra)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(goldenQuote, forKey: .goldenQuote)
        try container.encodeIfPresent(emotionalTone, forKey: .emotionalTone)
        try container.encodeIfPresent(generationBridge, forKey: .generationBridge)
        try container.encode(passions, forKey: .passions)
        try container.encode(peopleMentioned, forKey: .peopleMentioned)
        try container.encodeIfPresent(grokImaginePrompt, forKey: .grokImaginePrompt)
        try container.encodeIfPresent(rawTranscript, forKey: .rawTranscript)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}
