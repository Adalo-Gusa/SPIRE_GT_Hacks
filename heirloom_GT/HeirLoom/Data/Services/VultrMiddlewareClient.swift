import Foundation

/// Client for the HeirLoom FastAPI middleware (`middleware/server.py`). The middleware owns MongoDB Atlas
/// storage, Backboard memory, and Grok calls, so the app never holds those credentials.
actor VultrMiddlewareClient: LoomAgentServiceProtocol, StorybookServiceProtocol {
    private let baseURL: URL
    private let apiKey: String?
    private let session: URLSession

    init(baseURL: URL, apiKey: String?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - Graph endpoints (used by FamilyGraphRepository)

    func fetchGraph() async throws -> FamilyGraph {
        try await session.decoded(FamilyGraph.self, for: .json("GET", url: endpoint("graph"), bearerToken: apiKey))
    }

    func addMemory(_ memory: MemoryNode) async throws {
        let request = try URLRequest.json("POST", url: endpoint("memories"), body: memory, bearerToken: apiKey)
        _ = try await session.validatedData(for: request)
    }

    func pendingSparks(for memberID: UUID) async throws -> [LoomSpark] {
        let url = endpoint("sparks/\(memberID.uuidString)")
        return try await session.decoded([LoomSpark].self, for: .json("GET", url: url, bearerToken: apiKey))
    }

    func resolveSpark(id: UUID) async throws {
        let request = URLRequest.json("POST", url: endpoint("sparks/\(id.uuidString)/resolve"), bearerToken: apiKey)
        _ = try await session.validatedData(for: request)
    }

    // MARK: - LoomAgentServiceProtocol

    func ingestMemory(transcript: String, authorID: UUID) async throws -> MemoryIngestionResult {
        let body = IngestRequest(transcript: transcript, authorID: authorID)
        let request = try URLRequest.json("POST", url: endpoint("memories/ingest"), body: body, bearerToken: apiKey)
        return try await session.decoded(MemoryIngestionResult.self, for: request)
    }

    func followUpQuestions(for memory: MemoryNode, sessionID: String) async throws -> [String] {
        let body = FollowUpRequest(memory: memory, sessionID: sessionID)
        let request = try URLRequest.json("POST", url: endpoint("agent/followups"), body: body, bearerToken: apiKey)
        return try await session.decoded(FollowUpResponse.self, for: request).questions
    }

    /// Expects the middleware to stream plain-text chunks, one per line.
    nonisolated func streamReply(to message: String, sessionID: String) -> AsyncThrowingStream<String, any Error> {
        let url = endpoint("agent/chat")
        let body = ChatRequest(message: message, sessionID: sessionID)
        let apiKey = apiKey
        let session = session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try URLRequest.json("POST", url: url, body: body, bearerToken: apiKey)
                    for try await line in try await session.validatedLines(for: request) {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - StorybookServiceProtocol

    func generateStorybook(memoryIDs: [UUID]) async throws -> [StoryChapter] {
        let request = try URLRequest.json("POST", url: endpoint("storybook"), body: StorybookRequest(memoryIDs: memoryIDs), bearerToken: apiKey)
        return try await session.decoded([StoryChapter].self, for: request)
    }

    func generateIllustration(prompt: String) async throws -> URL {
        let request = try URLRequest.json("POST", url: endpoint("storybook/illustration"), body: IllustrationRequest(prompt: prompt), bearerToken: apiKey)
        return try await session.decoded(IllustrationResponse.self, for: request).url
    }

    // MARK: - Private

    private nonisolated func endpoint(_ path: String) -> URL {
        baseURL.appending(path: path)
    }
}

// MARK: - Wire types

private struct IngestRequest: Encodable, Sendable {
    let transcript: String
    let authorID: UUID

    enum CodingKeys: String, CodingKey {
        case transcript
        case authorID = "author_id"
    }
}

private struct FollowUpRequest: Encodable, Sendable {
    let memory: MemoryNode
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case memory
        case sessionID = "session_id"
    }
}

private struct FollowUpResponse: Decodable, Sendable {
    let questions: [String]
}

private struct ChatRequest: Encodable, Sendable {
    let message: String
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case message
        case sessionID = "session_id"
    }
}

private struct StorybookRequest: Encodable, Sendable {
    let memoryIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case memoryIDs = "memory_ids"
    }
}

private struct IllustrationRequest: Encodable, Sendable {
    let prompt: String
}

private struct IllustrationResponse: Decodable, Sendable {
    let url: URL
}
