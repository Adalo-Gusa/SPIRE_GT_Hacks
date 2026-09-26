import Foundation
import Observation

/// Generated storybook chapters and their Grok Imagine scene cards.
@MainActor
@Observable
final class StorybookViewModel {
    private(set) var chapters: [StoryChapter] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var regeneratingChapterIDs: Set<UUID> = []

    private let service: any StorybookServiceProtocol

    init(service: any StorybookServiceProtocol) {
        self.service = service
    }

    /// Pass an empty array to weave the whole family archive.
    func load(memoryIDs: [UUID] = []) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            chapters = try await service.generateStorybook(memoryIDs: memoryIDs)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func regenerateIllustration(for chapter: StoryChapter) async {
        guard !regeneratingChapterIDs.contains(chapter.id) else { return }
        regeneratingChapterIDs.insert(chapter.id)
        defer { regeneratingChapterIDs.remove(chapter.id) }
        do {
            let url = try await service.generateIllustration(prompt: "\(chapter.title). \(chapter.narrativeText)")
            if let index = chapters.firstIndex(where: { $0.id == chapter.id }) {
                chapters[index].illustrationURL = url
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
