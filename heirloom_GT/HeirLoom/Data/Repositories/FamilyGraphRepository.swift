import Foundation

/// Live graph repository: fetches from the middleware, caches the latest snapshot, and
/// fans changes out to every `graphUpdates()` subscriber.
actor FamilyGraphRepository: FamilyGraphRepositoryProtocol {
    private let client: VultrMiddlewareClient
    private var cachedGraph: FamilyGraph?
    private var subscribers: [UUID: AsyncStream<FamilyGraph>.Continuation] = [:]

    init(client: VultrMiddlewareClient) {
        self.client = client
    }

    func fetchGraph() async throws -> FamilyGraph {
        let graph = try await client.fetchGraph()
        update(graph)
        return graph
    }

    func add(_ memory: MemoryNode) async throws {
        try await client.addMemory(memory)
        guard var graph = cachedGraph else { return }
        graph.memories.append(memory)
        update(graph)
    }

    func pendingSparks(for memberID: UUID) async throws -> [LoomSpark] {
        try await client.pendingSparks(for: memberID)
    }

    func resolveSpark(id: UUID) async throws {
        try await client.resolveSpark(id: id)
        guard var graph = cachedGraph, let index = graph.sparks.firstIndex(where: { $0.id == id }) else { return }
        graph.sparks[index].isResolved = true
        update(graph)
    }

    /// Emits the cached snapshot if there is one. Callers load the first snapshot with `fetchGraph()`,
    /// so a failed load surfaces as an error instead of an endless spinner.
    func graphUpdates() async -> AsyncStream<FamilyGraph> {
        let (stream, continuation) = AsyncStream.makeStream(of: FamilyGraph.self, bufferingPolicy: .bufferingNewest(1))
        let subscriberID = UUID()
        subscribers[subscriberID] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(subscriberID) }
        }
        if let cachedGraph {
            continuation.yield(cachedGraph)
        }
        return stream
    }

    // MARK: - Private

    private func update(_ graph: FamilyGraph) {
        cachedGraph = graph
        for continuation in subscribers.values {
            continuation.yield(graph)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}
