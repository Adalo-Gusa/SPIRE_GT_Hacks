import Foundation

struct HobbyConnection: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    var fromMemberID: UUID
    var toMemberID: UUID
    var sharedInterest: String
    var matchRationale: String
    var sourceMemoryID: UUID?

    init(
        id: UUID = UUID(),
        fromMemberID: UUID,
        toMemberID: UUID,
        sharedInterest: String,
        matchRationale: String,
        sourceMemoryID: UUID? = nil
    ) {
        self.id = id
        self.fromMemberID = fromMemberID
        self.toMemberID = toMemberID
        self.sharedInterest = sharedInterest
        self.matchRationale = matchRationale
        self.sourceMemoryID = sourceMemoryID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fromMemberID = "from_member_id"
        case toMemberID = "to_member_id"
        case sharedInterest = "shared_interest"
        case matchRationale = "match_rationale"
        case sourceMemoryID = "source_memory_id"
    }
}
