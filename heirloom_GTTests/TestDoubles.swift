import Foundation
@testable import heirloom_GT

struct TestError: Error, LocalizedError {
    var errorDescription: String? { "test failure" }
}

actor FakeRecorder: AudioRecordingServiceProtocol {
    var duration: TimeInterval
    var startDelay: Duration
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastFileURL: URL?
    private var isRecording = false
    private var meter: AsyncStream<Float>.Continuation?

    init(duration: TimeInterval = 2, startDelay: Duration = .zero) {
        self.duration = duration
        self.startDelay = startDelay
    }

    func requestPermission() async -> Bool { true }

    func startRecording() async throws -> URL {
        startCount += 1
        if startDelay > .zero { try await Task.sleep(for: startDelay) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: url.path, contents: Data([0, 1, 2]))
        lastFileURL = url
        isRecording = true
        return url
    }

    func stopRecording() async throws -> (fileURL: URL, duration: TimeInterval) {
        guard isRecording, let lastFileURL else { throw AudioRecordingError.notRecording }
        stopCount += 1
        isRecording = false
        meter?.finish()
        return (lastFileURL, duration)
    }

    func cancelRecording() async {
        isRecording = false
        meter?.finish()
    }

    func meteringStream() async -> AsyncStream<Float> {
        let (stream, continuation) = AsyncStream.makeStream(of: Float.self)
        meter = continuation
        return stream
    }

    /// Simulates an audio interruption: the recorder ends the metering stream on its own.
    func interrupt() {
        meter?.finish()
    }
}

actor FakeTranscriber: TranscriptionServiceProtocol {
    enum Behavior: Sendable {
        case text(String)
        case fail(TranscriptionError)
        case failGeneric
    }

    var behavior: Behavior

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func transcribe(audioAt url: URL) async throws -> String {
        switch behavior {
        case .text(let text): return text
        case .fail(let error): throw error
        case .failGeneric: throw TestError()
        }
    }
}

actor FakeAgent: LoomAgentServiceProtocol {
    var failIngest: Bool
    private(set) var ingestedTranscripts: [String] = []
    nonisolated let replyFails: Bool

    init(failIngest: Bool = false, replyFails: Bool = false) {
        self.failIngest = failIngest
        self.replyFails = replyFails
    }

    func setFailIngest(_ value: Bool) {
        failIngest = value
    }

    func ingestMemory(transcript: String, authorID: UUID) async throws -> MemoryIngestionResult {
        if failIngest { throw TestError() }
        ingestedTranscripts.append(transcript)
        return MemoryIngestionResult(memory: MemoryNode(
            authorID: authorID,
            rawTranscript: transcript,
            narrativeSummary: "Summary",
            extractedEra: "1960s"
        ))
    }

    func followUpQuestions(for memory: MemoryNode, sessionID: String) async throws -> [String] {
        ["Who taught you?"]
    }

    nonisolated func streamReply(to message: String, sessionID: String) -> AsyncThrowingStream<String, any Error> {
        let fails = replyFails
        return AsyncThrowingStream { continuation in
            if fails {
                continuation.finish(throwing: TestError())
            } else {
                continuation.yield("Tell ")
                continuation.yield("me more.")
                continuation.finish()
            }
        }
    }
}
