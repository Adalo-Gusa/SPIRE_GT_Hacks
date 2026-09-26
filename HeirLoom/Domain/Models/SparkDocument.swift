import Foundation

/// Actionable intergenerational connection alert,
/// mapped 1:1 to the MongoDB Atlas `sparks` collection.
struct SparkDocument: Identifiable, Codable, Equatable, Sendable {
    var id: String { _id }
    var _id: String
    var familyId: String
    var elderId: String
    var targetMemberId: String
    var matchedPassion: String
    var sparkMessage: String
    var ctaAction: String
    var isRead: Bool
    var status: String
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case _id
        case id
        case familyId = "family_id"
        case altFamilyId = "familyId"
        case elderId = "elder_id"
        case altElderId = "elderId"
        case targetMemberId = "target_member_id"
        case altTargetMemberId = "targetMemberId"
        case matchedPassion = "matched_passion"
        case altMatchedPassion = "matchedPassion"
        case sparkMessage = "spark_message"
        case altSparkMessage = "sparkMessage"
        case ctaAction = "cta_action"
        case altCtaAction = "ctaAction"
        case isRead = "is_read"
        case altIsRead = "isRead"
        case status
        case createdAt = "created_at"
        case altCreatedAt = "createdAt"
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        elderId: String,
        targetMemberId: String,
        matchedPassion: String,
        sparkMessage: String,
        ctaAction: String,
        isRead: Bool = false,
        status: String = "active",
        createdAt: Date? = Date()
    ) {
        self._id = id
        self.familyId = familyId
        self.elderId = elderId
        self.targetMemberId = targetMemberId
        self.matchedPassion = matchedPassion
        self.sparkMessage = sparkMessage
        self.ctaAction = ctaAction
        self.isRead = isRead
        self.status = status
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let primaryId = try? container.decode(String.self, forKey: ._id)
        let altId = try? container.decode(String.self, forKey: .id)
        self._id = primaryId ?? altId ?? UUID().uuidString

        let fam = try? container.decode(String.self, forKey: .familyId)
        let altFam = try? container.decode(String.self, forKey: .altFamilyId)
        self.familyId = fam ?? altFam ?? "fam_clarke_001"

        let elder = try? container.decode(String.self, forKey: .elderId)
        let altElder = try? container.decode(String.self, forKey: .altElderId)
        self.elderId = elder ?? altElder ?? "member_grandpa_joe"

        let target = try? container.decode(String.self, forKey: .targetMemberId)
        let altTarget = try? container.decode(String.self, forKey: .altTargetMemberId)
        self.targetMemberId = target ?? altTarget ?? "member_alex"

        let passion = try? container.decode(String.self, forKey: .matchedPassion)
        let altPassion = try? container.decode(String.self, forKey: .altMatchedPassion)
        self.matchedPassion = passion ?? altPassion ?? "General"

        let msg = try? container.decode(String.self, forKey: .sparkMessage)
        let altMsg = try? container.decode(String.self, forKey: .altSparkMessage)
        self.sparkMessage = msg ?? altMsg ?? ""

        let cta = try? container.decode(String.self, forKey: .ctaAction)
        let altCta = try? container.decode(String.self, forKey: .altCtaAction)
        self.ctaAction = cta ?? altCta ?? "Explore Memory"

        let read = try? container.decode(Bool.self, forKey: .isRead)
        let altRead = try? container.decode(Bool.self, forKey: .altIsRead)
        self.isRead = read ?? altRead ?? false

        self.status = (try? container.decode(String.self, forKey: .status)) ?? "active"

        self.createdAt = (try? container.decode(Date.self, forKey: .createdAt))
            ?? (try? container.decode(Date.self, forKey: .altCreatedAt))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_id, forKey: ._id)
        try container.encode(familyId, forKey: .familyId)
        try container.encode(elderId, forKey: .elderId)
        try container.encode(targetMemberId, forKey: .targetMemberId)
        try container.encode(matchedPassion, forKey: .matchedPassion)
        try container.encode(sparkMessage, forKey: .sparkMessage)
        try container.encode(ctaAction, forKey: .ctaAction)
        try container.encode(isRead, forKey: .isRead)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}
