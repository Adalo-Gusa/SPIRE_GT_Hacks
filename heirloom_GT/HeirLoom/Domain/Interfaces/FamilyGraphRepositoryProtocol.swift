import Foundation

protocol FamilyGraphRepositoryProtocol: Sendable {
    func fetchGraph() async throws -> FamilyGraph
    func add(_ memory: MemoryNode) async throws
    func pendingSparks(for memberID: UUID) async throws -> [LoomSpark]
    func resolveSpark(id: UUID) async throws
    /// Emits the latest snapshot immediately, then every time the graph changes.
    func graphUpdates() async -> AsyncStream<FamilyGraph>
}
