import Foundation
import Testing
@testable import heirloom_GT

@MainActor
struct LoomVoiceViewModelTests {
    private func makeViewModel(
        recorder: FakeRecorder = FakeRecorder(),
        transcriber: FakeTranscriber = FakeTranscriber(.text("I built a radio in 1962.")),
        agent: FakeAgent = FakeAgent()
    ) -> LoomVoiceViewModel {
        LoomVoiceViewModel(
            recorder: recorder,
            transcriber: transcriber,
            agent: agent,
            repository: MockDataService(latency: .zero),
            authorID: MockIDs.joseph
        )
    }

    @Test func recordingIsTranscribedSavedAndCleanedUp() async throws {
        let recorder = FakeRecorder()
        let agent = FakeAgent()
        let viewModel = makeViewModel(recorder: recorder, agent: agent)

        await viewModel.beginPushToTalk()
        #expect(viewModel.state == .recording)
        await viewModel.endPushToTalk()

        #expect(viewModel.state == .reviewing)
        #expect(viewModel.transcript == "I built a radio in 1962.")
        #expect(viewModel.lastIngestion?.memory.rawTranscript == "I built a radio in 1962.")
        #expect(viewModel.followUpQuestions == ["Who taught you?"])
        #expect(await agent.ingestedTranscripts == ["I built a radio in 1962."])
        let fileURL = try #require(await recorder.lastFileURL)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func tooShortRecordingIsDiscarded() async {
        let agent = FakeAgent()
        let viewModel = makeViewModel(recorder: FakeRecorder(duration: 0.2), agent: agent)

        await viewModel.beginPushToTalk()
        await viewModel.endPushToTalk()

        #expect(viewModel.state == .idle)
        #expect(await agent.ingestedTranscripts.isEmpty)
    }

    @Test func emptyTranscriptFailsAndSavesNothing() async {
        let agent = FakeAgent()
        let viewModel = makeViewModel(transcriber: FakeTranscriber(.text("   ")), agent: agent)

        await viewModel.beginPushToTalk()
        await viewModel.endPushToTalk()

        #expect(viewModel.state == .failed(TranscriptionError.noSpeech.localizedDescription))
        #expect(viewModel.lastIngestion == nil)
        #expect(!viewModel.canRetrySave)
        #expect(await agent.ingestedTranscripts.isEmpty)
    }

    @Test func transcriptionErrorsNeverFallBackToSampleStory() async {
        let agent = FakeAgent()
        let viewModel = makeViewModel(transcriber: FakeTranscriber(.failGeneric), agent: agent)

        await viewModel.beginPushToTalk()
        await viewModel.endPushToTalk()

        #expect(viewModel.state == .failed(TranscriptionError.noSpeech.localizedDescription))
        #expect(viewModel.transcript.isEmpty)
        #expect(await agent.ingestedTranscripts.isEmpty)
    }

    @Test func permissionErrorIsShownAsIs() async {
        let viewModel = makeViewModel(transcriber: FakeTranscriber(.fail(.permissionDenied)))

        await viewModel.beginPushToTalk()
        await viewModel.endPushToTalk()

        #expect(viewModel.state == .failed(TranscriptionError.permissionDenied.localizedDescription))
    }

    @Test func failedSaveKeepsTranscriptAndCanRetry() async {
        let agent = FakeAgent(failIngest: true)
        let viewModel = makeViewModel(agent: agent)

        await viewModel.beginPushToTalk()
        await viewModel.endPushToTalk()

        #expect(viewModel.canRetrySave)
        #expect(viewModel.transcript == "I built a radio in 1962.")

        await agent.setFailIngest(false)
        await viewModel.retrySave()

        #expect(viewModel.state == .reviewing)
        #expect(await agent.ingestedTranscripts == ["I built a radio in 1962."])
    }

    @Test func releaseDuringSlowStartStillStopsOnce() async {
        let recorder = FakeRecorder(startDelay: .milliseconds(100))
        let viewModel = makeViewModel(recorder: recorder)

        let begin = Task { await viewModel.beginPushToTalk() }
        while await recorder.startCount == 0 {
            await Task.yield()
        }
        await viewModel.endPushToTalk()
        await begin.value

        #expect(viewModel.state == .reviewing)
        #expect(await recorder.stopCount == 1)
    }

    @Test func interruptionFinishesTheRecording() async throws {
        let recorder = FakeRecorder()
        let viewModel = makeViewModel(recorder: recorder)

        await viewModel.beginPushToTalk()
        await recorder.interrupt()

        for _ in 0..<200 where viewModel.state != .reviewing {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(viewModel.state == .reviewing)
        #expect(await recorder.stopCount == 1)
    }

    @Test func replyErrorKeepsReview() async throws {
        let viewModel = makeViewModel(agent: FakeAgent(replyFails: true))
        await viewModel.beginPushToTalk()
        await viewModel.endPushToTalk()

        viewModel.sendFollowUp("It was 1962.")
        for _ in 0..<200 where viewModel.isStreamingReply {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(viewModel.state == .reviewing)
        #expect(viewModel.replyError == "test failure")
    }

    @Test func replyStreamsIntoAgentReply() async throws {
        let viewModel = makeViewModel()
        await viewModel.beginPushToTalk()
        await viewModel.endPushToTalk()

        viewModel.sendFollowUp("It was 1962.")
        for _ in 0..<200 where viewModel.isStreamingReply {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(viewModel.agentReply == "Tell me more.")
        #expect(viewModel.replyError == nil)
    }
}
