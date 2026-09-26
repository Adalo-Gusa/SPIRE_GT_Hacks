import Foundation

struct StoryChapter: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var narrativeText: String
    var illustrationURL: URL?
    var audioSnippetURL: URL?
    var sourceMemoryIDs: [UUID]

    init(
        id: UUID = UUID(),
        title: String,
        narrativeText: String,
        illustrationURL: URL? = nil,
        audioSnippetURL: URL? = nil,
        sourceMemoryIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.narrativeText = narrativeText
        self.illustrationURL = illustrationURL
        self.audioSnippetURL = audioSnippetURL
        self.sourceMemoryIDs = sourceMemoryIDs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case narrativeText = "narrative_text"
        case illustrationURL = "illustration_url"
        case audioSnippetURL = "audio_snippet_url"
        case sourceMemoryIDs = "source_memory_ids"
    }
}
