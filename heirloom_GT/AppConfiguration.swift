import Foundation

enum AppConfiguration {
    static let backboardAPIKey = secret("BACKBOARD_API_KEY")
    static let grokAPIKey = secret("XAI_API_KEY")

    /// Live Backboard REST host. `https://api.backboard.io/v1` does not resolve.
    static let backboardBaseURL = URL(string: "https://app.backboard.io/api")!
    static let grokBaseURL = URL(string: "https://api.x.ai/v1")!

    /// Persistent family-session assistant on Backboard (memories are assistant-scoped).
    static let defaultAssistantId = "3de074d9-d6b6-4139-9d31-e12d9a5bebf2"

    /// Current xAI chat model. `grok-beta` / `grok-2` are no longer served on this key.
    static let grokModel = "grok-4.3"

    static let grokVoiceModel = "grok-voice-latest"
    static let grokVoiceName = "eve"
    static let grokVoiceSampleRate: Double = 24_000
    /// How long you can pause before Loomie treats your turn as finished and answers (milliseconds).
    /// Longer lets people think mid-story without being cut off; shorter makes replies snappier.
    static let grokVoiceSilenceMs = 3_000
    static let grokRealtimeURL = URL(string: "wss://api.x.ai/v1/realtime?model=\(grokVoiceModel)")!
    static let grokClientSecretsURL = URL(string: "https://api.x.ai/v1/realtime/client_secrets")!

    static let loomieSystemPrompt = """
    You are Loomie, a warm family oral historian in a back-and-forth conversation.

    Greetings and small talk: greet them like a person. Do not start an interview yet. Invite them to share a memory whenever they are ready.

    Stories and facts: remember people, places, years, jobs, and feelings from this conversation. Acknowledge a specific detail. You may ask one gentle follow-up.

    Recall: if they ask what they told you, who they mentioned, or where something happened, answer from this conversation and the known family memories. Never say you forgot.

    Keep replies to 1–3 spoken sentences. Sound like a conversation, not a questionnaire.
    """

    static let loomieVoiceInstructions = """
    You are Loomie, a warm family oral historian speaking out loud in a live conversation.

    If they say hi, hello, or how are you, greet them back warmly and wait. Do not launch into interview questions until they share a story.

    Remember everything they say in this session. When they later ask what they told you, who was with them, or where they worked, answer from this conversation and the known family memories. Never say you forgot or that you have no memory.

    When they share a story, acknowledge a concrete detail and you may ask one gentle follow-up. Keep spoken replies to 1–3 sentences.
    """

    // MARK: - MongoDB Atlas Configuration
    static let mongoDBDatabase = secret("MONGODB_DATABASE").isEmpty ? "heirloom_db" : secret("MONGODB_DATABASE")
    static let mongoDBCluster = secret("MONGODB_CLUSTER").isEmpty ? "TestCluster" : secret("MONGODB_CLUSTER")
    static let mongoDBFamilyId = secret("HEIRLOOM_FAMILY_ID").isEmpty ? "fam_clarke_001" : secret("HEIRLOOM_FAMILY_ID")
    static let atlasDataAPIKey = secret("ATLAS_DATA_API_KEY")
    static let atlasDataAPIBaseURL = URL(string: secret("ATLAS_DATA_API_URL").isEmpty
        ? "https://data.mongodb-api.com/app/data-heirloom/endpoint/data/v1"
        : secret("ATLAS_DATA_API_URL"))!

    // MARK: - Secrets

    /// Reads a key from the Xcode scheme's environment variables, then from the bundled,
    /// gitignored `Secrets.env` (KEY=VALUE lines). Returns "" when neither has it.
    private static func secret(_ name: String) -> String {
        if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty {
            return value
        }
        return bundledSecrets[name] ?? ""
    }

    private static let bundledSecrets: [String: String] = {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "env"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return [:] }

        var values: [String: String] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            values[key] = value
        }
        return values
    }()
}
