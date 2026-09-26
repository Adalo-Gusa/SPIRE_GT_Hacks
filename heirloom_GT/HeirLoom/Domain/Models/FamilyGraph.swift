import Foundation

/// Immutable snapshot of the whole family knowledge graph.
struct FamilyGraph: Codable, Sendable, Hashable {
    var members: [FamilyMember]
    var memories: [MemoryNode]
    var kinshipEdges: [KinshipEdge]
    var hobbyConnections: [HobbyConnection]
    var sparks: [LoomSpark]

    init(
        members: [FamilyMember] = [],
        memories: [MemoryNode] = [],
        kinshipEdges: [KinshipEdge] = [],
        hobbyConnections: [HobbyConnection] = [],
        sparks: [LoomSpark] = []
    ) {
        self.members = members
        self.memories = memories
        self.kinshipEdges = kinshipEdges
        self.hobbyConnections = hobbyConnections
        self.sparks = sparks
    }

    static let empty = FamilyGraph()

    func member(id: UUID) -> FamilyMember? {
        members.first { $0.id == id }
    }

    func memory(id: UUID) -> MemoryNode? {
        memories.first { $0.id == id }
    }

    func members(in tier: GenerationTier) -> [FamilyMember] {
        members.filter { $0.generationTier == tier }
    }

    func memories(authoredBy memberID: UUID) -> [MemoryNode] {
        memories.filter { $0.authorID == memberID }.sorted { $0.timestamp > $1.timestamp }
    }

    func connections(involving memberID: UUID) -> [HobbyConnection] {
        hobbyConnections.filter { $0.fromMemberID == memberID || $0.toMemberID == memberID }
    }

    func pendingSparks(for memberID: UUID) -> [LoomSpark] {
        sparks.filter { $0.targetMemberID == memberID && !$0.isResolved }.sorted { $0.timestamp > $1.timestamp }
    }

    enum CodingKeys: String, CodingKey {
        case members
        case memories
        case kinshipEdges = "kinship_edges"
        case hobbyConnections = "hobby_connections"
        case sparks
    }
}

/// Everything produced when a new oral memory is processed.
struct MemoryIngestionResult: Codable, Sendable, Hashable {
    var memory: MemoryNode
    var newConnections: [HobbyConnection]
    var sparks: [LoomSpark]

    init(memory: MemoryNode, newConnections: [HobbyConnection] = [], sparks: [LoomSpark] = []) {
        self.memory = memory
        self.newConnections = newConnections
        self.sparks = sparks
    }

    enum CodingKeys: String, CodingKey {
        case memory
        case newConnections = "new_connections"
        case sparks
    }
}
