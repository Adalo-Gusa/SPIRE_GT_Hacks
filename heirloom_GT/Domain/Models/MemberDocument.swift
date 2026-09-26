import Foundation

/// Represents a family member node in the HeirLoom corkboard tree,
/// mapped 1:1 with the MongoDB Atlas `members` collection.
struct MemberDocument: Identifiable, Codable, Equatable, Sendable {
    var id: String { _id }
    var _id: String
    var familyId: String
    var name: String
    var birthYear: Int
    var generationTier: Int
    var spouseId: String?
    var parents: [String]
    var children: [String]
    var passions: [String]
    var avatarUrl: String?
    /// "female" or "male"; picks the girl or guy placeholder drawing. Members without one get the guy.
    var gender: String?
    var bio: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case _id
        case id
        case familyId = "family_id"
        case altFamilyId = "familyId"
        case name
        case birthYear = "birth_year"
        case altBirthYear = "birthYear"
        case generationTier = "generation_tier"
        case altGenerationTier = "generationTier"
        case spouseId = "spouse_id"
        case altSpouseId = "spouseId"
        case parents
        case children
        case passions
        case avatarUrl = "avatar_url"
        case altAvatarUrl = "avatarUrl"
        case gender
        case bio
        case createdAt = "created_at"
        case altCreatedAt = "createdAt"
        case updatedAt = "updated_at"
        case altUpdatedAt = "updatedAt"
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        name: String,
        birthYear: Int,
        generationTier: Int,
        spouseId: String? = nil,
        parents: [String] = [],
        children: [String] = [],
        passions: [String] = [],
        avatarUrl: String? = nil,
        gender: String? = nil,
        bio: String? = nil,
        createdAt: Date? = Date(),
        updatedAt: Date? = Date()
    ) {
        self._id = id
        self.familyId = familyId
        self.name = name
        self.birthYear = birthYear
        self.generationTier = generationTier
        self.spouseId = spouseId
        self.parents = parents
        self.children = children
        self.passions = passions
        self.avatarUrl = avatarUrl
        self.gender = gender
        self.bio = bio
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let primaryId = try? container.decode(String.self, forKey: ._id)
        let altId = try? container.decode(String.self, forKey: .id)
        self._id = primaryId ?? altId ?? UUID().uuidString

        let fam = try? container.decode(String.self, forKey: .familyId)
        let altFam = try? container.decode(String.self, forKey: .altFamilyId)
        self.familyId = fam ?? altFam ?? "fam_clarke_001"

        self.name = try container.decode(String.self, forKey: .name)

        let by = try? container.decode(Int.self, forKey: .birthYear)
        let altBy = try? container.decode(Int.self, forKey: .altBirthYear)
        self.birthYear = by ?? altBy ?? 1970

        let gt = try? container.decode(Int.self, forKey: .generationTier)
        let altGt = try? container.decode(Int.self, forKey: .altGenerationTier)
        self.generationTier = gt ?? altGt ?? 1

        self.spouseId = (try? container.decode(String.self, forKey: .spouseId))
            ?? (try? container.decode(String.self, forKey: .altSpouseId))

        self.parents = (try? container.decode([String].self, forKey: .parents)) ?? []
        self.children = (try? container.decode([String].self, forKey: .children)) ?? []
        self.passions = (try? container.decode([String].self, forKey: .passions)) ?? []

        self.avatarUrl = (try? container.decode(String.self, forKey: .avatarUrl))
            ?? (try? container.decode(String.self, forKey: .altAvatarUrl))
        self.gender = try? container.decode(String.self, forKey: .gender)

        self.bio = try? container.decode(String.self, forKey: .bio)
        self.createdAt = (try? container.decode(Date.self, forKey: .createdAt))
            ?? (try? container.decode(Date.self, forKey: .altCreatedAt))
        self.updatedAt = (try? container.decode(Date.self, forKey: .updatedAt))
            ?? (try? container.decode(Date.self, forKey: .altUpdatedAt))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_id, forKey: ._id)
        try container.encode(familyId, forKey: .familyId)
        try container.encode(name, forKey: .name)
        try container.encode(birthYear, forKey: .birthYear)
        try container.encode(generationTier, forKey: .generationTier)
        try container.encodeIfPresent(spouseId, forKey: .spouseId)
        try container.encode(parents, forKey: .parents)
        try container.encode(children, forKey: .children)
        try container.encode(passions, forKey: .passions)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    /// The drawn girl or guy shown in place of a photo (the stored avatar URLs are stock photos, not family).
    var placeholderImageName: String {
        gender?.lowercased() == "female" ? "PlaceholderGirl" : "PlaceholderGuy"
    }

}
