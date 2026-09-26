import Foundation

enum LoomError: LocalizedError {
    case invalidURL
    case httpStatus(Int, String)
    case emptyReply
    case decoding(String)
    case missingAPIKey(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build a request URL."
        case .httpStatus(let code, let body):
            return "HTTP \(code): \(body)"
        case .emptyReply:
            return "Grok returned an empty reply."
        case .decoding(let detail):
            return "Could not decode a response: \(detail)"
        case .missingAPIKey(let name):
            return "\(name) is not set. Add it to heirloom_GT/Secrets.env or the scheme's environment variables."
        }
    }
}

struct ActiveStoryContext: Equatable {
    var detectedEra: String?
    var detectedLocation: String?
    var peopleMentioned: Set<String> = []
    var coreTopics: Set<String> = []

    var isEmpty: Bool {
        detectedEra == nil && detectedLocation == nil && peopleMentioned.isEmpty && coreTopics.isEmpty
    }

    var promptBlock: String {
        guard !isEmpty else { return "" }
        var lines: [String] = ["Active Story Context (Anchors established earlier in this session):"]
        if let era = detectedEra { lines.append("- Era / Timeframe: \(era)") }
        if let loc = detectedLocation { lines.append("- Location / Setting: \(loc)") }
        if !peopleMentioned.isEmpty { lines.append("- People in this story: \(peopleMentioned.sorted().joined(separator: ", "))") }
        if !coreTopics.isEmpty { lines.append("- Crafts / Topics: \(coreTopics.sorted().joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }

    mutating func update(from text: String) {
        // Detect 4-digit years or decade references
        if detectedEra == nil {
            let yearPattern = #"\b(19\d{2}|20\d{2})\b"#
            if let match = text.range(of: yearPattern, options: .regularExpression) {
                detectedEra = String(text[match])
            } else {
                let decadePattern = #"\b('?\d0s|nineteen \w+|sixties|seventies|eighties|fifties)\b"#
                if let match = text.range(of: decadePattern, options: [.regularExpression, .caseInsensitive]) {
                    detectedEra = String(text[match])
                }
            }
        }

        // Detect common family kinship terms
        let kinshipTerms = [
            "brother", "sister", "mother", "father", "dad", "mom", "uncle", "aunt",
            "grandpa", "grandma", "cousin", "wife", "husband", "daughter", "son", "roommate"
        ]
        let lower = text.lowercased()
        for term in kinshipTerms {
            if lower.contains(term) && !peopleMentioned.contains(term.capitalized) {
                peopleMentioned.insert(term.capitalized)
            }
        }
    }
}

actor LoomService {
    static let shared = LoomService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var conversations: [String: [GrokMessage]] = [:]
    private var storyContexts: [String: ActiveStoryContext] = [:]

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
        self.encoder = JSONEncoder()
    }

    func recallMemories(query: String, threadId: String) async -> [String] {
        await fetchMemories(query: query, threadId: threadId)
    }

    func rememberIfNeeded(_ text: String, threadId: String) async -> Bool {
        let utterance = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ConversationMemory.shouldStore(utterance) else {
            print("[Loomie] skipped small-talk memory: \(utterance)")
            return false
        }
        do {
            try await persistMemory(text: utterance, threadId: threadId)
            return true
        } catch {
            print("[Loomie] memory persist failed: \(error.localizedDescription)")
            return false
        }
    }

    func rememberStory(_ text: String, threadId: String) async {
        _ = await rememberIfNeeded(text, threadId: threadId)
    }

    /// Conversational turn: keep live history, recall long-term facts, persist new ones.
    func sendMessage(text: String, threadId: String) async throws -> String {
        let utterance = text.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[Loomie] sendMessage thread=\(threadId) text=\(utterance)")

        // Update active story tracker anchors so context survives beyond the 16-turn message limit
        var ctx = storyContexts[threadId] ?? ActiveStoryContext()
        ctx.update(from: utterance)
        storyContexts[threadId] = ctx

        let memories = await fetchMemories(query: utterance, threadId: threadId)
        print("[Loomie] recalled \(memories.count) memories")

        let history = conversations[threadId] ?? []
        let reply = try await completeWithGrok(userText: utterance, threadId: threadId, memories: memories, history: history)

        var next = history
        next.append(GrokMessage(role: "user", content: utterance))
        next.append(GrokMessage(role: "assistant", content: reply))
        if next.count > 16 {
            next = Array(next.suffix(16))
        }
        conversations[threadId] = next

        if ConversationMemory.shouldStore(utterance) {
            try? await persistMemory(text: utterance, threadId: threadId)
        }
        return reply
    }

    // MARK: - Memory recall

    private func fetchMemories(query: String, threadId: String) async -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        func appendMemories(_ list: [BackboardMemory]) {
            for memory in list {
                let text = memory.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let key = memory.id ?? text
                if !seen.contains(key) {
                    seen.insert(key)
                    ordered.append(text)
                }
            }
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty, let searched = try? await searchMemories(query: trimmedQuery) {
            appendMemories(searched)
        }

        if let listed = try? await listMemories() {
            appendMemories(listed)
        }

        if !threadId.isEmpty {
            print("[Loomie] memory pool for thread \(threadId): \(ordered)")
        }
        return ordered
    }

    private func searchMemories(query: String) async throws -> [BackboardMemory] {
        let assistantID = AppConfiguration.defaultAssistantId
        let url = AppConfiguration.backboardBaseURL
            .appendingPathComponent("assistants")
            .appendingPathComponent(assistantID)
            .appendingPathComponent("memories")
            .appendingPathComponent("search")
        let body = BackboardSearchRequest(query: query, limit: 10)
        let envelope: BackboardMemoryList = try await postJSON(url: url, body: body, headers: backboardHeaders)
        return envelope.memories ?? []
    }

    private func listMemories() async throws -> [BackboardMemory] {
        let assistantID = AppConfiguration.defaultAssistantId
        let url = AppConfiguration.backboardBaseURL
            .appendingPathComponent("assistants")
            .appendingPathComponent(assistantID)
            .appendingPathComponent("memories")
        let envelope: BackboardMemoryList = try await getJSON(url: url, headers: backboardHeaders)
        return envelope.memories ?? []
    }

    // MARK: - Grok

    private func completeWithGrok(userText: String, threadId: String, memories: [String], history: [GrokMessage]) async throws -> String {
        let url = AppConfiguration.grokBaseURL.appendingPathComponent("chat/completions")
        let memoryBlock: String
        if memories.isEmpty {
            memoryBlock = "No prior family memories are on file for this speaker yet."
        } else {
            memoryBlock = "Known family memories. Use these when the speaker asks you to recall something, or to gently bridge shared passions:\n"
                + memories.map { "- \($0)" }.joined(separator: "\n")
        }

        var messages = [
            GrokMessage(role: "system", content: AppConfiguration.loomieSystemPrompt)
        ]

        // Inject active story context anchors so early details are never forgotten
        if let activeCtx = storyContexts[threadId], !activeCtx.isEmpty {
            messages.append(GrokMessage(role: "system", content: activeCtx.promptBlock))
        }

        messages.append(GrokMessage(role: "system", content: memoryBlock))
        messages.append(contentsOf: history)
        messages.append(GrokMessage(role: "user", content: userText))

        let request = GrokChatRequest(
            model: AppConfiguration.grokModel,
            messages: messages,
            temperature: 0.8,
            maxTokens: 220,
            reasoningEffort: "none"
        )

        let response: GrokChatResponse = try await postJSON(url: url, body: request, headers: grokHeaders)
        let reply = response.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !reply.isEmpty else { throw LoomError.emptyReply }
        print("[Loomie] grok reply: \(reply)")
        return reply
    }

    func extractStoryArtifact(from transcript: String) async throws -> StoryArtifact {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LoomError.decoding("The conversation has no story to save.")
        }
        print("[Loomie] extracting story artifact")
        let url = AppConfiguration.grokBaseURL.appendingPathComponent("chat/completions")
        let messages = [
            GrokMessage(role: "system", content: Self.archivistPrompt),
            GrokMessage(role: "user", content: trimmed)
        ]
        let request = GrokJSONChatRequest(
            model: AppConfiguration.grokModel,
            messages: messages,
            temperature: 0.2,
            maxTokens: 900,
            reasoningEffort: "none"
        )
        let response: GrokChatResponse = try await postJSON(url: url, body: request, headers: grokHeaders)
        let raw = response.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        print("[Loomie] extraction raw: \(raw)")
        guard !raw.isEmpty else { throw LoomError.emptyReply }
        return try Self.decodeStoryArtifact(from: raw, transcript: trimmed)
    }

    /// Stores a biographical summary on the assistant, so a new thread can recall it.
    func commitPermanentMemory(assistantId: String, factSummary: String) async throws {
        let fact = factSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fact.isEmpty else { throw LoomError.decoding("There is no fact summary to store.") }
        print("[Loomie] committing permanent memory assistant=\(assistantId)")
        let url = AppConfiguration.backboardBaseURL
            .appendingPathComponent("assistants")
            .appendingPathComponent(assistantId)
            .appendingPathComponent("memories")
        let body = BackboardAddMemoryRequest(
            content: fact,
            metadata: [
                "source": "loomie",
                "kind": "story_artifact",
                "scope": "assistant"
            ]
        )
        let _: BackboardAddMemoryResponse = try await postJSON(url: url, body: body, headers: backboardHeaders)
        print("[Loomie] permanent memory stored")
    }

    private static let archivistPrompt = """
    You are an empathetic, world-class biographical archivist. Analyze the following conversation between Loomie and an elder to preserve their family history. Extract the key historical, sensory, and biographical facts. Return ONLY a valid JSON object matching this schema:
    {
    "title": "Short poetic title (e.g., Rebuilding the '65 Mustang)",
    "narrativeSummary": "2-3 sentence core biographical summary capturing both facts and emotional feeling",
    "extractedEra": "Year, decade, or life stage if mentioned, or null",
    "location": "City, region, or landmark if mentioned, or null",
    "peopleMentioned": ["List of family/friends mentioned"],
    "passionsOrHobbies": ["Specific skills, trades, crafts, sports, or hobbies identified"],
    "goldenQuote": "The single most memorable, poignant verbatim sentence spoken by the storyteller that captures the emotional heart of this memory, or null",
    "emotionalTone": "Emotional tone (e.g., nostalgic triumph, bittersweet resilience, warm humor)",
    "generationBridge": "A 1-sentence thought on which younger family member or kinship passion this memory bridges to, or null",
    "grokImaginePrompt": "A vivid, warm vintage Polaroid or 35mm film aesthetic prompt capturing the central scene without text or modern elements"
    }
    """

    private static func decodeStoryArtifact(from raw: String, transcript: String) throws -> StoryArtifact {
        let jsonText = extractJSONObject(from: raw)
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoomError.decoding("Story JSON could not be parsed. body=\(raw)")
        }
        func text(_ keys: String...) -> String? {
            for key in keys {
                guard let value = object[key] as? String else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed.lowercased() != "null" {
                    return trimmed
                }
            }
            return nil
        }
        func list(_ keys: String...) -> [String] {
            for key in keys {
                if let values = object[key] as? [String] {
                    return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                }
                if let values = object[key] as? [Any] {
                    return values.compactMap { $0 as? String }
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            }
            return []
        }
        guard let title = text("title"),
              let narrativeSummary = text("narrativeSummary", "narrative_summary"),
              let grokImaginePrompt = text("grokImaginePrompt", "grok_imagine_prompt") else {
            throw LoomError.decoding("Story JSON was missing title, summary, or imagine prompt. body=\(raw)")
        }
        return StoryArtifact(
            title: title,
            narrativeSummary: narrativeSummary,
            extractedEra: text("extractedEra", "extracted_era"),
            location: text("location"),
            peopleMentioned: list("peopleMentioned", "people_mentioned"),
            passionsOrHobbies: list("passionsOrHobbies", "passions_or_hobbies"),
            goldenQuote: text("goldenQuote", "golden_quote"),
            emotionalTone: text("emotionalTone", "emotional_tone"),
            generationBridge: text("generationBridge", "generation_bridge"),
            grokImaginePrompt: grokImaginePrompt,
            rawTranscript: transcript
        )
    }

    private static func extractJSONObject(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end else {
            return text
        }
        return String(text[start...end])
    }

    // MARK: - Memory persist

    private func persistMemory(text: String, threadId: String) async throws {
        try await addMemory(text: text, threadId: threadId)
        await persistViaAutoMemory(text: text, threadId: threadId)
    }

    private func addMemory(text: String, threadId: String) async throws {
        let assistantID = AppConfiguration.defaultAssistantId
        let url = AppConfiguration.backboardBaseURL
            .appendingPathComponent("assistants")
            .appendingPathComponent(assistantID)
            .appendingPathComponent("memories")
        let body = BackboardAddMemoryRequest(
            content: text,
            metadata: [
                "source": "loomie",
                "thread_id": threadId,
                "kind": "user_story"
            ]
        )
        let _: BackboardAddMemoryResponse = try await postJSON(url: url, body: body, headers: backboardHeaders)
        print("[Loomie] stored memory for thread \(threadId)")
    }

    /// Records the turn on a Backboard thread with `memory: "Auto"`.
    /// Extraction only runs when Backboard is allowed to call an LLM; we still fire it
    /// and rely on `addMemory` as the durable write.
    private func persistViaAutoMemory(text: String, threadId: String) async {
        let url = AppConfiguration.backboardBaseURL
            .appendingPathComponent("threads")
            .appendingPathComponent("messages")
        let body: [String: Any] = [
            "content": text,
            "assistant_id": AppConfiguration.defaultAssistantId,
            "memory": "Auto",
            "send_to_llm": "false",
            "stream": false,
            "metadata": [
                "source": "loomie",
                "session_thread_id": threadId
            ]
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            let _: BackboardMessageResponse = try await send(url: url, method: "POST", headers: backboardHeaders, body: data)
            print("[Loomie] Backboard memory: Auto recorded")
        } catch {
            print("[Loomie] memory: Auto persist skipped: \(error.localizedDescription)")
        }
    }

    // MARK: - HTTP

    private var backboardHeaders: [String: String] {
        [
            "X-API-Key": AppConfiguration.backboardAPIKey,
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }

    private var grokHeaders: [String: String] {
        [
            "Authorization": "Bearer \(AppConfiguration.grokAPIKey)",
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }

    private func getJSON<T: Decodable>(url: URL, headers: [String: String]) async throws -> T {
        try await send(url: url, method: "GET", headers: headers, body: nil)
    }

    private func postJSON<T: Decodable, B: Encodable>(url: URL, body: B, headers: [String: String]) async throws -> T {
        let data = try encoder.encode(body)
        return try await send(url: url, method: "POST", headers: headers, body: data)
    }

    private func send<T: Decodable>(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 60
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        print("[Loomie] → \(method) \(url.absoluteString)")
        if let body, let logged = String(data: body, encoding: .utf8) {
            print("[Loomie] → body \(logged)")
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        print("[Loomie] ← \(status) \(raw)")

        guard (200...299).contains(status) else {
            throw LoomError.httpStatus(status, raw)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LoomError.decoding("\(error) body=\(raw)")
        }
    }
}

// MARK: - DTOs

private struct BackboardSearchRequest: Encodable {
    let query: String
    let limit: Int
}

private struct BackboardAddMemoryRequest: Encodable {
    let content: String
    let metadata: [String: String]
}

private struct BackboardMemoryList: Decodable {
    let memories: [BackboardMemory]?
    let totalCount: Int?
}

private struct BackboardMemory: Decodable {
    let id: String?
    let content: String?
    let memory: String?
    let score: Double?

    var displayText: String {
        content ?? memory ?? ""
    }
}

private struct BackboardAddMemoryResponse: Decodable {
    let success: Bool?
    let memoryId: String?
    let content: String?
    let message: String?
}

private struct BackboardMessageResponse: Decodable {
    let threadId: String?
    let assistantId: String?
    let status: String?
    let memoryOperationId: String?
}

private struct GrokJSONChatRequest: Encodable {
    let model: String
    let messages: [GrokMessage]
    let temperature: Double
    let maxTokens: Int
    let reasoningEffort: String
    let responseFormat: [String: String]

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
        case responseFormat = "response_format"
    }

    init(model: String, messages: [GrokMessage], temperature: Double, maxTokens: Int, reasoningEffort: String) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.reasoningEffort = reasoningEffort
        self.responseFormat = ["type": "json_object"]
    }
}

private struct GrokChatRequest: Encodable {
    let model: String
    let messages: [GrokMessage]
    let temperature: Double
    let maxTokens: Int
    let reasoningEffort: String

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
    }
}

private struct GrokMessage: Encodable {
    let role: String
    let content: String
}

private struct GrokChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
    }

    let choices: [Choice]?
}

enum ConversationMemory {
    static func shouldStore(_ text: String) -> Bool {
        let collapsed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = collapsed.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !stripped.isEmpty else { return false }

        // Never store questions as biographical facts
        if text.contains("?") || isQuery(collapsed) {
            return false
        }

        // Never store meta-talk, UI references, or conversational filler
        if isFillerOrMeta(collapsed) {
            return false
        }

        let smallTalk: Set<String> = [
            "hi", "hello", "hey", "yo", "howdy", "hiya", "hi there",
            "hi loomie", "hello loomie", "hey loomie", "hey there",
            "good morning", "good afternoon", "good evening",
            "how are you", "how are you doing", "how's it going", "how is it going",
            "what's up", "whats up", "sup", "how are ya",
            "thanks", "thank you", "thanks loomie", "thank you loomie",
            "ok", "okay", "k", "sure", "yes", "yeah", "yep", "no", "nope",
            "bye", "goodbye", "see you", "good night", "goodnight",
            "i'm good", "im good", "i am good", "i'm fine", "im fine",
            "sounds good", "got it", "i see", "cool", "alright"
        ]
        if smallTalk.contains(stripped) { return false }

        return hasFactSignal(collapsed)
    }

    private static func isQuery(_ text: String) -> Bool {
        let questionStarters = [
            "what ", "whats ", "what's ", "where ", "where's ", "who ", "who's ",
            "when ", "why ", "how ", "do you ", "did you ", "can you ", "could you ",
            "tell me ", "remember ", "do you remember", "did i tell you"
        ]
        return questionStarters.contains { text.hasPrefix($0) }
    }

    private static func isFillerOrMeta(_ text: String) -> Bool {
        let metaPhrases = [
            "text bubble", "can you hear", "can you hear me", "microphone", "sound check",
            "four hours of sleep", "you got that", "i guess", "i think so", "wait a minute",
            "hold on", "testing", "one two three"
        ]
        return metaPhrases.contains { text.contains($0) }
    }

    private static func hasFactSignal(_ text: String) -> Bool {
        let needles = [
            "my ", "i was", "i am", "i'm ", "im ", "i worked", "i lived", "i grew",
            "brother", "sister", "mother", "father", "mom", "dad", "grandma", "grandpa",
            "uncle", "aunt", "cousin", "husband", "wife", "son", "daughter", "niece", "nephew",
            "in 19", "in 20", "years ago", "born", "school", "college", "university",
            "worked at", "lived in", "named", "family", "print shop", "restor", "mustang",
            "chicago", "fixing cars", "summer of", "married", "wedding", "job", "career",
            "retired", "hometown", "neighborhood", "military", "army", "navy", "air force"
        ]
        return needles.contains { text.contains($0) }
    }
}
