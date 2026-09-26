import Foundation
import Observation

/// Push-to-talk capture, transcription, ingestion, and follow-up dialogue with the Loom agent.
@MainActor
@Observable
final class LoomVoiceViewModel {
    enum RecordingState: Equatable {
        case idle
        case recording
        case processing
        case reviewing
        case failed(String)
    }

    static let minimumDuration: TimeInterval = 0.5
    static let fallbackFollowUp = "What happened next, and who was there with you?"

    private(set) var state: RecordingState = .idle
    private(set) var meterLevel: Float = 0
    private(set) var recordingStartedAt: Date?
    private(set) var transcript = ""
    private(set) var lastIngestion: MemoryIngestionResult?
    private(set) var followUpQuestions: [String] = []
    private(set) var agentReply = ""
    private(set) var isStreamingReply = false
    /// A failed reply is shown inline so the review stays on screen.
    private(set) var replyError: String?

    var authorID: UUID
    let sessionID: String

    private let recorder: any AudioRecordingServiceProtocol
    private let transcriber: any TranscriptionServiceProtocol
    private let agent: any LoomAgentServiceProtocol
    private let repository: any FamilyGraphRepositoryProtocol
    private var isStarting = false
    private var isStopping = false
    private var stopRequestedWhileStarting = false
    private var meteringTask: Task<Void, Never>?
    private var replyTask: Task<Void, Never>?

    init(
        recorder: any AudioRecordingServiceProtocol,
        transcriber: any TranscriptionServiceProtocol,
        agent: any LoomAgentServiceProtocol,
        repository: any FamilyGraphRepositoryProtocol,
        authorID: UUID,
        sessionID: String = UUID().uuidString
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.agent = agent
        self.repository = repository
        self.authorID = authorID
        self.sessionID = sessionID
    }

    var isRecording: Bool { state == .recording }

    /// True when a transcript exists but saving it failed, so the story can be retried without re-recording.
    var canRetrySave: Bool {
        if case .failed = state { return !transcript.isEmpty && lastIngestion == nil }
        return false
    }

    // MARK: - Push-to-talk

    func beginPushToTalk() async {
        guard !isStarting, !isStopping, state != .recording, state != .processing else { return }
        isStarting = true
        stopRequestedWhileStarting = false

        do {
            _ = try await recorder.startRecording()
            state = .recording
            recordingStartedAt = .now
            startMetering(await recorder.meteringStream())
        } catch {
            isStarting = false
            state = .failed(error.localizedDescription)
            return
        }

        isStarting = false
        if stopRequestedWhileStarting {
            await endPushToTalk()
        }
    }

    func endPushToTalk() async {
        if isStarting {
            stopRequestedWhileStarting = true
            return
        }
        guard state == .recording, !isStopping else { return }
        isStopping = true
        defer { isStopping = false }

        let recording: (fileURL: URL, duration: TimeInterval)
        do {
            recording = try await recorder.stopRecording()
        } catch {
            finishRecordingUI()
            state = .failed(error.localizedDescription)
            return
        }
        finishRecordingUI()

        guard recording.duration >= Self.minimumDuration else {
            try? FileManager.default.removeItem(at: recording.fileURL)
            state = .idle
            return
        }

        await process(audioAt: recording.fileURL)
    }

    func cancelRecording() async {
        await recorder.cancelRecording()
        finishRecordingUI()
        state = .idle
    }

    func retrySave() async {
        guard canRetrySave else { return }
        await ingest(transcript)
    }

    // MARK: - Dialogue

    func sendFollowUp(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        replyTask?.cancel()
        agentReply = ""
        replyError = nil
        isStreamingReply = true
        let stream = agent.streamReply(to: trimmed, sessionID: sessionID)
        replyTask = Task { [weak self] in
            do {
                for try await token in stream {
                    self?.agentReply += token
                }
            } catch is CancellationError {
            } catch {
                self?.replyError = error.localizedDescription
            }
            self?.isStreamingReply = false
        }
    }

    func reset() {
        replyTask?.cancel()
        state = .idle
        transcript = ""
        lastIngestion = nil
        followUpQuestions = []
        agentReply = ""
        replyError = nil
        isStreamingReply = false
    }

    // MARK: - Private

    private func process(audioAt url: URL) async {
        state = .processing
        transcript = ""
        lastIngestion = nil
        followUpQuestions = []
        defer { try? FileManager.default.removeItem(at: url) }

        let text: String
        do {
            text = try await transcriber.transcribe(audioAt: url).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as TranscriptionError {
            state = .failed(error.localizedDescription)
            return
        } catch {
            state = .failed(TranscriptionError.noSpeech.localizedDescription)
            return
        }
        guard !text.isEmpty else {
            state = .failed(TranscriptionError.noSpeech.localizedDescription)
            return
        }
        transcript = text
        await ingest(text)
    }

    private func ingest(_ text: String) async {
        state = .processing
        let ingestion: MemoryIngestionResult
        do {
            ingestion = try await agent.ingestMemory(transcript: text, authorID: authorID)
        } catch {
            state = .failed("Your story wasn't saved: \(error.localizedDescription)")
            return
        }
        lastIngestion = ingestion
        // Refresh the shared graph so the corkboard and sparks show the new memory.
        let repository = repository
        Task { _ = try? await repository.fetchGraph() }

        let questions = (try? await agent.followUpQuestions(for: ingestion.memory, sessionID: sessionID)) ?? []
        followUpQuestions = questions.isEmpty ? [Self.fallbackFollowUp] : questions
        state = .reviewing
    }

    private func startMetering(_ stream: AsyncStream<Float>) {
        meteringTask?.cancel()
        meteringTask = Task { [weak self] in
            for await level in stream {
                self?.meterLevel = level
            }
            // The recorder ends the stream on its own when the audio session is interrupted.
            guard !Task.isCancelled, let self, self.state == .recording, !self.isStopping else { return }
            // Finish from a fresh task: stopping cancels `meteringTask`, which must not cancel processing.
            self.meteringTask = nil
            Task { await self.endPushToTalk() }
        }
    }

    private func finishRecordingUI() {
        meteringTask?.cancel()
        meteringTask = nil
        meterLevel = 0
        recordingStartedAt = nil
    }
}
