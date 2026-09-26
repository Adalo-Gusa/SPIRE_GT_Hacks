import Foundation

/// Represents a social family moment or post in the Family Feed,
/// ingested from Instagram or composed directly within HeirLoom.
public struct FeedPostDocument: Identifiable, Codable, Equatable, Sendable {
    public var id: String { _id }
    public var _id: String
    public var familyId: String
    public var authorId: String
    public var authorName: String
    public var authorAvatarUrl: String?
    public var content: String
    public var imageUrl: String?
    public var postUrl: String?
    public var source: String // "instagram" or "in_app"
    public var passions: [String]
    public var location: String?
    public var createdAt: Date
    public var isUnread: Bool

    public enum CodingKeys: String, CodingKey {
        case _id
        case id
        case familyId = "family_id"
        case altFamilyId = "familyId"
        case authorId = "author_id"
        case altAuthorId = "authorId"
        case authorName = "author_name"
        case altAuthorName = "authorName"
        case authorAvatarUrl = "author_avatar_url"
        case altAuthorAvatarUrl = "authorAvatarUrl"
        case content
        case imageUrl = "image_url"
        case altImageUrl = "imageUrl"
        case postUrl = "post_url"
        case altPostUrl = "postUrl"
        case source
        case passions
        case location
        case createdAt = "created_at"
        case altCreatedAt = "createdAt"
        case isUnread = "is_unread"
        case altIsUnread = "isUnread"
    }

    public init(
        id: String = UUID().uuidString,
        familyId: String = "fam_clarke_001",
        authorId: String,
        authorName: String,
        authorAvatarUrl: String? = nil,
        content: String,
        imageUrl: String? = nil,
        postUrl: String? = nil,
        source: String = "in_app",
        passions: [String] = [],
        location: String? = nil,
        createdAt: Date = Date(),
        isUnread: Bool = true
    ) {
        self._id = id
        self.familyId = familyId
        self.authorId = authorId
        self.authorName = authorName
        self.authorAvatarUrl = authorAvatarUrl
        self.content = content
        self.imageUrl = imageUrl
        self.postUrl = postUrl
        self.source = source
        self.passions = passions
        self.location = location
        self.createdAt = createdAt
        self.isUnread = isUnread
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let primaryId = try? container.decode(String.self, forKey: ._id)
        let altId = try? container.decode(String.self, forKey: .id)
        self._id = primaryId ?? altId ?? UUID().uuidString

        let fam = try? container.decode(String.self, forKey: .familyId)
        let altFam = try? container.decode(String.self, forKey: .altFamilyId)
        self.familyId = fam ?? altFam ?? "fam_clarke_001"

        let authId = try? container.decode(String.self, forKey: .authorId)
        let altAuthId = try? container.decode(String.self, forKey: .altAuthorId)
        self.authorId = authId ?? altAuthId ?? "unknown_member"

        let name = try? container.decode(String.self, forKey: .authorName)
        let altName = try? container.decode(String.self, forKey: .altAuthorName)
        self.authorName = name ?? altName ?? "Family Member"

        let avatar = try? container.decode(String.self, forKey: .authorAvatarUrl)
        let altAvatar = try? container.decode(String.self, forKey: .altAuthorAvatarUrl)
        self.authorAvatarUrl = avatar ?? altAvatar

        self.content = (try? container.decode(String.self, forKey: .content)) ?? ""

        let img = try? container.decode(String.self, forKey: .imageUrl)
        let altImg = try? container.decode(String.self, forKey: .altImageUrl)
        self.imageUrl = img ?? altImg

        let pUrl = try? container.decode(String.self, forKey: .postUrl)
        let altPUrl = try? container.decode(String.self, forKey: .altPostUrl)
        self.postUrl = pUrl ?? altPUrl

        self.source = (try? container.decode(String.self, forKey: .source)) ?? "in_app"
        self.passions = (try? container.decode([String].self, forKey: .passions)) ?? []
        self.location = try? container.decode(String.self, forKey: .location)

        let date = try? container.decode(Date.self, forKey: .createdAt)
        let altDate = try? container.decode(Date.self, forKey: .altCreatedAt)
        self.createdAt = date ?? altDate ?? Date()

        let unread = try? container.decode(Bool.self, forKey: .isUnread)
        let altUnread = try? container.decode(Bool.self, forKey: .altIsUnread)
        self.isUnread = unread ?? altUnread ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_id, forKey: ._id)
        try container.encode(familyId, forKey: .familyId)
        try container.encode(authorId, forKey: .authorId)
        try container.encode(authorName, forKey: .authorName)
        try container.encodeIfPresent(authorAvatarUrl, forKey: .authorAvatarUrl)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(postUrl, forKey: .postUrl)
        try container.encode(source, forKey: .source)
        try container.encode(passions, forKey: .passions)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isUnread, forKey: .isUnread)
    }
}
