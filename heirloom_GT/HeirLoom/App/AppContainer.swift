import Foundation
import Observation

/// Composition root. Builds protocol-typed services for the configured mode and owns the long-lived
/// ViewModels so tab switches keep their state.
@MainActor
@Observable
final class AppContainer {
    let configuration: AppConfiguration

    let audioRecorder: any AudioRecordingServiceProtocol
    let transcriber: any TranscriptionServiceProtocol
    let graphRepository: any FamilyGraphRepositoryProtocol
    let loomAgent: any LoomAgentServiceProtocol
    let storybookService: any StorybookServiceProtocol
    /// Only set in mock mode, where it powers the corkboard's demo button.
    let mockData: MockDataService?

    let loomVoiceViewModel: LoomVoiceViewModel
    let corkboardViewModel: CorkboardViewModel
    let storybookViewModel: StorybookViewModel
    let sparkViewModel: SparkNotificationViewModel

    init(configuration: AppConfiguration) {
        self.configuration = configuration

        let audioRecorder = AudioRecorderService()
        let transcriber: any TranscriptionServiceProtocol
        let graphRepository: any FamilyGraphRepositoryProtocol
        let loomAgent: any LoomAgentServiceProtocol
        let storybookService: any StorybookServiceProtocol
        let mockData: MockDataService?

        if configuration.isMockMode {
            let mock = MockDataService(latency: configuration.mockLatency)
            transcriber = mock
            graphRepository = mock
            loomAgent = mock
            storybookService = mock
            mockData = mock
        } else {
            let client = VultrMiddlewareClient(baseURL: configuration.middlewareBaseURL, apiKey: configuration.middlewareToken)
            transcriber = SpeechTranscriptionService()
            graphRepository = FamilyGraphRepository(client: client)
            loomAgent = client
            storybookService = client
            mockData = nil
        }

        self.audioRecorder = audioRecorder
        self.transcriber = transcriber
        self.graphRepository = graphRepository
        self.loomAgent = loomAgent
        self.storybookService = storybookService
        self.mockData = mockData

        self.loomVoiceViewModel = LoomVoiceViewModel(
            recorder: audioRecorder,
            transcriber: transcriber,
            agent: loomAgent,
            repository: graphRepository,
            authorID: configuration.defaultStorytellerID
        )
        self.corkboardViewModel = CorkboardViewModel(repository: graphRepository, demo: mockData)
        self.storybookViewModel = StorybookViewModel(service: storybookService)
        self.sparkViewModel = SparkNotificationViewModel(
            repository: graphRepository,
            activeMemberID: configuration.activeMemberID
        )
    }

    static func preview() -> AppContainer {
        AppContainer(configuration: .preview)
    }
}
