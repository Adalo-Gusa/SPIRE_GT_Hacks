import SwiftUI

/// Represents a photo card node on the conspiracy corkboard family tree.
public struct CorkboardNode: Identifiable, Equatable, Sendable {
    public let id: String
    public let member: MemberDocument
    public var position: CGPoint
    public var size: CGSize
    public var pinPoint: CGPoint
    public var rotationDegrees: Double
    public var pinColorHex: String

    public var x: CGFloat { position.x }
    public var y: CGFloat { position.y }

    public init(
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
public struct CorkboardString: Identifiable, Equatable, Sendable {
    public enum StringType: String, Codable, Sendable {
        case spouse = "spouse"
        case parentChild = "parent-child"
        case passionConnection = "connection"
    }

    public let id: String
    public let type: StringType
    public let fromMemberId: String
    public let toMemberId: String
    public let fromPoint: CGPoint
    public let toPoint: CGPoint
    public let sagAmount: CGFloat
    public let colorHex: String
    public let label: String?

    public init(
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
public struct CorkboardLayoutState: Equatable, Sendable {
    public var nodes: [CorkboardNode]
    public var strings: [CorkboardString]
    public var canvasSize: CGSize

    public init(
        nodes: [CorkboardNode] = [],
        strings: [CorkboardString] = [],
        canvasSize: CGSize = CGSize(width: 1400, height: 1000)
    ) {
        self.nodes = nodes
        self.strings = strings
        self.canvasSize = canvasSize
    }
}
