import Foundation

public enum SharedPostStatus: String, Codable {
    case pending
    case processing
    case ingested
    case failed
}

/// Data transfer object passed from the Share Extension to the main app via App Group storage.
public struct SharedPostPayload: Identifiable, Codable, Sendable {
    public let id: String
    public let source: String           // "instagram"
    public let caption: String
    public let postURL: String?
    public let imageFileName: String?   // Relative file path inside App Group folder
    public let authorId: String         // e.g. "member_alex_clarke"
    public let authorName: String       // e.g. "Alex Clarke"
    public let timestamp: Date
    public var status: SharedPostStatus

    public init(
        id: String = UUID().uuidString,
        source: String = "instagram",
        caption: String,
        postURL: String? = nil,
        imageFileName: String? = nil,
        authorId: String = "member_alex_clarke",
        authorName: String = "Alex Clarke",
        timestamp: Date = Date(),
        status: SharedPostStatus = .pending
    ) {
        self.id = id
        self.source = source
        self.caption = caption
        self.postURL = postURL
        self.imageFileName = imageFileName
        self.authorId = authorId
        self.authorName = authorName
        self.timestamp = timestamp
        self.status = status
    }
}
