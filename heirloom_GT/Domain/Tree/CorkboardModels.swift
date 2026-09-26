import SwiftUI

/// Represents a photo card node on the conspiracy corkboard family tree.
struct CorkboardNode: Identifiable, Equatable, Sendable {
    let id: String
    let member: MemberDocument
    var position: CGPoint
    var size: CGSize
    var pinPoint: CGPoint
    var rotationDegrees: Double
    var pinColorHex: String

    var x: CGFloat { position.x }
    var y: CGFloat { position.y }

    init(
        id: String,
        member: MemberDocument,
        position: CGPoint,
        size: CGSize = CGSize(width: 150, height: 180),
        pinPoint: CGPoint,
        rotationDegrees: Double = 0.0,
        pinColorHex: String = "#e84118"
    ) {
        self.id = id
        self.member = member
        self.position = position
        self.size = size
        self.pinPoint = pinPoint
        self.rotationDegrees = rotationDegrees
        self.pinColorHex = pinColorHex
    }
}

/// Represents an authentic red twine / string connecting two evidence pins on the corkboard.
struct CorkboardString: Identifiable, Equatable, Sendable {
    enum StringType: String, Codable, Sendable {
        case spouse = "spouse"
        case parentChild = "parent-child"
        case passionConnection = "connection"
    }

    let id: String
    let type: StringType
    let fromMemberId: String
    let toMemberId: String
    let fromPoint: CGPoint
    let toPoint: CGPoint
    let sagAmount: CGFloat
    let colorHex: String
    let label: String?

    init(
        id: String,
        type: StringType,
        fromMemberId: String,
        toMemberId: String,
        fromPoint: CGPoint,
        toPoint: CGPoint,
        sagAmount: CGFloat = 20.0,
        colorHex: String = "#d63031",
        label: String? = nil
    ) {
        self.id = id
        self.type = type
        self.fromMemberId = fromMemberId
        self.toMemberId = toMemberId
        self.fromPoint = fromPoint
        self.toPoint = toPoint
        self.sagAmount = sagAmount
        self.colorHex = colorHex
        self.label = label
    }
}

/// The state produced by the corkboard auto-orientation layout engine.
struct CorkboardLayoutState: Equatable, Sendable {
    var nodes: [CorkboardNode]
    var strings: [CorkboardString]
    var canvasSize: CGSize

    init(
        nodes: [CorkboardNode] = [],
        strings: [CorkboardString] = [],
        canvasSize: CGSize = CGSize(width: 1400, height: 1000)
    ) {
        self.nodes = nodes
        self.strings = strings
        self.canvasSize = canvasSize
    }
}
