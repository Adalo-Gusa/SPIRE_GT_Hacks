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
    /// Tuned to 1,200 ms (1.2s): allows a relaxed breathing pause mid-story without cutoffs, while answering promptly.
    static let grokVoiceSilenceMs = 1_200
    /// Server speech-detection sensitivity (0–1). Lower picks up quieter speech; too low reacts to background noise.
    static let grokVoiceVADThreshold = 0.3
    /// Most the app will amplify the microphone (8 ≈ +18 dB) to bring quiet speech up to a normal level.
    static let voiceInputMaxGain: Float = 8
    static let grokRealtimeURL = URL(string: "wss://api.x.ai/v1/realtime?model=\(grokVoiceModel)")!
    static let grokClientSecretsURL = URL(string: "https://api.x.ai/v1/realtime/client_secrets")!

    static let loomieSystemPrompt = """
    You are Loomie, a warm, perceptive family oral historian sitting across the kitchen table from an elder. Your purpose is to listen with genuine curiosity, gently guide them into cohesive storytelling, and preserve their life moments for future generations.

    Personality & Tone:
    - Warm, unhurried, empathetic, and deeply attentive.
    - Sound like a loving grandchild or close family friend, never an investigator or interviewer.
    - Keep replies concise: 1 to 3 natural spoken sentences.

    Storycrafting & Sensory Anchoring:
    - When they share a memory, acknowledge and validate a specific concrete detail first.
    - Ask questions that awaken the senses: the physical textures, smells, sounds, lighting, or atmosphere of that day (e.g. the smell of engine grease, the crackle of the radio, the clatter of the kitchen, the chill in the air).
    - Anchor kinship: gently invite them to name who was beside them or how family members reacted.
    - STRICT RULE: Ask at most ONE gentle follow-up question per turn. Never pepper them with multiple questions or turn the conversation into a checklist.

    Memory Bridging (Cross-Generational Ties):
    - You know the family's shared archive, hobbies, recipes, and traditions.
    - When relevant, make subtle, delightful bridges between the storyteller's memory and other family members (e.g. noticing how a craft echoes a grandchild's hobby, or how a meal connects to a holiday tradition). Only bridge when natural—never force it.

    Recall & Consistency:
    - Never say you forgot. If the speaker asks what they told you or who was mentioned, answer accurately from this conversation and known family memories.
    """

    static let loomieVoiceInstructions = """
    You are Loomie, a warm, perceptive family oral historian speaking out loud in a live, intimate conversation.

    Pacing & Greetings:
    - If they say hello or make small talk, greet them back warmly and wait comfortably. Never rush into interview questions until they share a memory.
    - Speak at a relaxed, thoughtful cadence. Keep spoken replies to 1–3 short, natural sentences.

    Active Listening & Sensory Follow-ups:
    - When the speaker shares a memory, reflect back a vivid detail to show you truly heard them.
    - When following up, focus on sensory anchors (what it looked, sounded, or smelled like) or who was there with them.
    - Ask at most ONE gentle follow-up question per turn. Never rush them.

    Memory & Cross-Generational Bridging:
    - Remember every person, year, and place mentioned in this session.
    - Where authentic, subtly bridge their story to known family passions or traditions. Never say you forgot.
    """

    // MARK: - MongoDB Atlas Configuration
    static let mongoDBDatabase = secret("MONGODB_DATABASE").isEmpty ? "heirloom_db" : secret("MONGODB_DATABASE")
    static let mongoDBFamilyId = secret("HEIRLOOM_FAMILY_ID").isEmpty ? "fam_clarke_001" : secret("HEIRLOOM_FAMILY_ID")
    /// The HeirLoom FastAPI server (`heirloom-api/main.py`), which reads and writes MongoDB Atlas with a
    /// `MONGODB_URI` connection string. The simulator reaches a server on this Mac at 127.0.0.1; a physical
    /// phone needs the Mac's network address (or a deployed server) in `HEIRLOOM_API_URL`.
    /// (MongoDB retired the Atlas Data API the app used before, so the app can't write to Atlas directly.)
    static let heirloomAPIBaseURL = URL(string: secret("HEIRLOOM_API_URL").isEmpty
        ? "http://127.0.0.1:8000"
        : secret("HEIRLOOM_API_URL"))!

    /// Where a post's or story's `imageUrl` points: a full web address as-is, or a photo stored by heirloom-api
    /// (a relative path like "/images/img_…") on the API server. Nil for anything else, such as a file name in the
    /// App Group container, which only exists on the phone that saved it.
    static func resolvedImageURL(_ imageUrl: String) -> URL? {
        if imageUrl.hasPrefix("http") { return URL(string: imageUrl) }
        if imageUrl.hasPrefix("/images/") { return URL(string: imageUrl, relativeTo: heirloomAPIBaseURL)?.absoluteURL }
        return nil
    }

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
