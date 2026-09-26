import Foundation

/// The conversational "Loom" agent: memory extraction and follow-up dialogue.
protocol LoomAgentServiceProtocol: Sendable {
    /// Extracts a `MemoryNode` from a transcript and returns any new hobby bridges and sparks it produced.
    func ingestMemory(transcript: String, authorID: UUID) async throws -> MemoryIngestionResult
    func followUpQuestions(for memory: MemoryNode, sessionID: String) async throws -> [String]
    /// Streams the agent's reply token by token. `sessionID` keys persistent multi-session memory.
    func streamReply(to message: String, sessionID: String) -> AsyncThrowingStream<String, any Error>
}
