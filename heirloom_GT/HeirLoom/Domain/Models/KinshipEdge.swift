import Foundation

enum KinshipRelation: String, Codable, Sendable, Hashable, CaseIterable {
    case parent
    case child
    case spouse
    case sibling
}

/// Directed edge: `fromID` is the `relationType` of `toID` (e.g. from Joseph, to Marcus, `.parent`).
struct KinshipEdge: Codable, Sendable, Hashable, Identifiable {
    var fromID: UUID
    var toID: UUID
    var relationType: KinshipRelation

    var id: String { "\(fromID.uuidString)-\(relationType.rawValue)-\(toID.uuidString)" }

    init(fromID: UUID, toID: UUID, relationType: KinshipRelation) {
        self.fromID = fromID
        self.toID = toID
        self.relationType = relationType
    }

    enum CodingKeys: String, CodingKey {
        case fromID = "from_id"
        case toID = "to_id"
        case relationType = "relation_type"
    }
}
