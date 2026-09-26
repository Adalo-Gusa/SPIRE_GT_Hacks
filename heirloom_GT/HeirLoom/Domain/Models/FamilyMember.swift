import Foundation

enum GenerationTier: Int, Codable, Sendable, Hashable, CaseIterable, Comparable {
    case grandparents = 1
    case parents = 2
    case grandchildren = 3

    var displayName: String {
        switch self {
        case .grandparents: "Grandparents"
        case .parents: "Parents"
        case .grandchildren: "Grandchildren"
        }
    }

    static func < (lhs: GenerationTier, rhs: GenerationTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct FamilyMember: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var generationTier: GenerationTier
    var relationshipLabel: String?
    var bio: String
    var profileImageURL: URL?
    var passionTags: [String]
    var phoneNumber: String?

    init(
        id: UUID = UUID(),
        name: String,
        generationTier: GenerationTier,
        relationshipLabel: String? = nil,
        bio: String = "",
        profileImageURL: URL? = nil,
        passionTags: [String] = [],
        phoneNumber: String? = nil
    ) {
        self.id = id
        self.name = name
        self.generationTier = generationTier
        self.relationshipLabel = relationshipLabel
        self.bio = bio
        self.profileImageURL = profileImageURL
        self.passionTags = passionTags
        self.phoneNumber = phoneNumber
    }

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case generationTier = "generation_tier"
        case relationshipLabel = "relationship_label"
        case bio
        case profileImageURL = "profile_image_url"
        case passionTags = "passion_tags"
        case phoneNumber = "phone_number"
    }
}
