import Foundation

protocol StorybookServiceProtocol: Sendable {
    /// Weaves the given memories into illustrated chapters. An empty array means "use the whole family archive".
    func generateStorybook(memoryIDs: [UUID]) async throws -> [StoryChapter]
    func generateIllustration(prompt: String) async throws -> URL
}
