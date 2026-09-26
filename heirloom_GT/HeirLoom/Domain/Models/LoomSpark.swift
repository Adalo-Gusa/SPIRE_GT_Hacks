import Foundation

enum SparkActionType: String, Codable, Sendable, Hashable, CaseIterable {
    case callPhone = "call_phone"
    case sendVoiceNote = "send_voice_note"
    case viewStory = "view_story"

    var callToAction: String {
        switch self {
        case .callPhone: "Call"
        case .sendVoiceNote: "Send a voice note"
        case .viewStory: "View story"
        }
    }
}

/// A proactive nudge that bridges generations, e.g. telling a grandchild that a grandparent just shared a related skill.
struct LoomSpark: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    var targetMemberID: UUID
    var elderID: UUID
    var promptText: String
    var actionType: SparkActionType
    var timestamp: Date
    var relatedMemoryID: UUID?
    var isResolved: Bool

    init(
        id: UUID = UUID(),
        targetMemberID: UUID,
        elderID: UUID,
        promptText: String,
        actionType: SparkActionType,
        timestamp: Date = .now,
        relatedMemoryID: UUID? = nil,
        isResolved: Bool = false
    ) {
        self.id = id
        self.targetMemberID = targetMemberID
        self.elderID = elderID
        self.promptText = promptText
        self.actionType = actionType
        self.timestamp = timestamp
        self.relatedMemoryID = relatedMemoryID
        self.isResolved = isResolved
    }

    enum CodingKeys: String, CodingKey {
        case id
        case targetMemberID = "target_member_id"
        case elderID = "elder_id"
        case promptText = "prompt_text"
        case actionType = "action_type"
        case timestamp
        case relatedMemoryID = "related_memory_id"
        case isResolved = "is_resolved"
    }
}
