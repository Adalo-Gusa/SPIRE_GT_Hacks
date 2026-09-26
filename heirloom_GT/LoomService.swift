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

actor LoomService {
    static let shared = LoomService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var conversations: [String: [GrokMessage]] = [:]

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

        let memories = await fetchMemories(query: utterance, threadId: threadId)
        print("[Loomie] recalled \(memories.count) memories")

        let history = conversations[threadId] ?? []
        let reply = try await completeWithGrok(userText: utterance, memories: memories, history: history)

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
        var byID: [String: String] = [:]

        if let searched = try? await searchMemories(query: query) {
            merge(searched, into: &byID)
        }

        if let listed = try? await listMemories() {
            merge(listed, into: &byID)
        }

        let facts = Array(byID.values).filter { !$0.isEmpty }
        if !threadId.isEmpty {
            print("[Loomie] memory pool for thread \(threadId): \(facts)")
        }
        return facts
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

    private func merge(_ memories: [BackboardMemory], into bag: inout [String: String]) {
        for memory in memories {
            let text = memory.displayText
            guard !text.isEmpty else { continue }
            bag[memory.id ?? text] = text
        }
    }

    // MARK: - Grok

    private func completeWithGrok(userText: String, memories: [String], history: [GrokMessage]) async throws -> String {
        let url = AppConfiguration.grokBaseURL.appendingPathComponent("chat/completions")
        let memoryBlock: String
        if memories.isEmpty {
            memoryBlock = "No prior family memories are on file for this speaker yet."
        } else {
            memoryBlock = "Known family memories. Use these when the speaker asks you to recall something:\n"
                + memories.map { "- \($0)" }.joined(separator: "\n")
        }

        var messages = [
            GrokMessage(role: "system", content: AppConfiguration.loomieSystemPrompt),
            GrokMessage(role: "system", content: memoryBlock)
        ]
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

        let smallTalk: Set<String> = [
            "hi", "hello", "hey", "yo", "howdy", "hiya", "hi there",
            "hi loomie", "hello loomie", "hey loomie", "hey there",
            "good morning", "good afternoon", "good evening",
            "how are you", "how are you doing", "how's it going", "how is it going",
            "what's up", "whats up", "sup", "how are ya",
            "thanks", "thank you", "thanks loomie", "thank you loomie",
            "ok", "okay", "k", "sure", "yes", "yeah", "yep", "no", "nope",
            "bye", "goodbye", "see you", "good night", "goodnight",
            "i'm good", "im good", "i am good", "i'm fine", "im fine"
        ]
        if smallTalk.contains(stripped) { return false }

        if hasFactSignal(collapsed) { return true }
        return stripped.split(whereSeparator: { $0.isWhitespace }).count >= 6
    }

    private static func hasFactSignal(_ text: String) -> Bool {
        let needles = [
            "my ", "i was", "i am", "i'm ", "im ", "i worked", "i lived", "i grew",
            "brother", "sister", "mother", "father", "mom", "dad", "grandma", "grandpa",
            "uncle", "aunt", "cousin", "husband", "wife", "son", "daughter",
            "in 19", "in 20", "years ago", "born", "school", "worked at", "lived in",
            "named", "family", "print shop"
        ]
        return needles.contains { text.contains($0) }
    }
}
