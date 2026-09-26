import Foundation

struct StoryArtifact: Identifiable, Codable, Equatable {
    var id: String
    let title: String
    let narrativeSummary: String
    let extractedEra: String?
    let location: String?
    let peopleMentioned: [String]
    let passionsOrHobbies: [String]
    let grokImaginePrompt: String
    let rawTranscript: String
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        narrativeSummary: String,
        extractedEra: String?,
        location: String?,
        peopleMentioned: [String],
        passionsOrHobbies: [String],
        grokImaginePrompt: String,
        rawTranscript: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.narrativeSummary = narrativeSummary
        self.extractedEra = extractedEra
        self.location = location
        self.peopleMentioned = peopleMentioned
        self.passionsOrHobbies = passionsOrHobbies
        self.grokImaginePrompt = grokImaginePrompt
        self.rawTranscript = rawTranscript
        self.createdAt = createdAt
    }

    /// Assistant-scoped text stored in Backboard so a later thread can recall the story.
    var permanentFactSummary: String {
        let era = extractedEra ?? "unspecified"
        let place = location ?? "unspecified"
        let people = peopleMentioned.isEmpty ? "none named" : peopleMentioned.joined(separator: ", ")
        let passions = passionsOrHobbies.isEmpty ? "none named" : passionsOrHobbies.joined(separator: ", ")
        return "Biographical memory. \(title). \(narrativeSummary) Era: \(era). Location: \(place). People: \(people). Passions and hobbies: \(passions)."
    }
}
