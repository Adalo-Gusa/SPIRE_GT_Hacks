import Foundation
import Observation

/// Graph state for the spatial corkboard: members, kinship edges, and hobby bridges.
@MainActor
@Observable
final class CorkboardViewModel {
    private(set) var graph: FamilyGraph = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isSimulating = false
    var selectedMemberID: UUID?

    private let repository: any FamilyGraphRepositoryProtocol
    private let demo: MockDataService?

    init(repository: any FamilyGraphRepositoryProtocol, demo: MockDataService?) {
        self.repository = repository
        self.demo = demo
    }

    var canSimulateDemo: Bool { demo != nil }

    var membersByTier: [(tier: GenerationTier, members: [FamilyMember])] {
        GenerationTier.allCases.compactMap { tier -> (tier: GenerationTier, members: [FamilyMember])? in
            let members = graph.members(in: tier)
            return members.isEmpty ? nil : (tier, members)
        }
    }

    var selectedMember: FamilyMember? {
        selectedMemberID.flatMap(graph.member(id:))
    }

    func name(for memberID: UUID) -> String {
        graph.member(id: memberID)?.name ?? "Unknown"
    }

    /// Loads the graph, then mirrors repository updates until the calling task is cancelled. Call from `.task`.
    func observeGraph() async {
        let updates = await repository.graphUpdates()
        if graph.members.isEmpty {
            isLoading = true
            await refresh()
            isLoading = false
        }
        for await snapshot in updates {
            graph = snapshot
            errorMessage = nil
        }
    }

    func refresh() async {
        do {
            graph = try await repository.fetchGraph()
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func simulateRadioStory() async {
        guard let demo, !isSimulating else { return }
        isSimulating = true
        defer { isSimulating = false }
        await demo.simulateIngestionOfRadioStory()
    }
}
