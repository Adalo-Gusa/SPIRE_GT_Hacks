import SwiftUI
import Observation

/// A photo on the board. Positions are in board units (the 435pt-wide Figma frame) and scaled to the screen.
struct BoardPhoto: Identifiable {
    let id: UUID
    var memberId: String?
    var center: CGPoint
    var rotation: Angle
    var imageName: String?
    /// A remote photo (e.g. a family member's avatar); shown when there's no bundled `imageName`.
    var imageURL: URL?
    var caption: String?

    init(
        id: UUID = UUID(),
        memberId: String? = nil,
        center: CGPoint,
        rotation: Angle = .zero,
        imageName: String? = nil,
        imageURL: URL? = nil,
        caption: String? = nil
    ) {
        self.id = id
        self.memberId = memberId
        self.center = center
        self.rotation = rotation
        self.imageName = imageName
        self.imageURL = imageURL
        self.caption = caption
    }
}

/// A pin stuck into a photo. It rides along when the photo moves or rotates.
struct BoardPin: Identifiable {
    let id: UUID
    var photoID: BoardPhoto.ID
    /// Where the pin sits relative to the photo's center, in the photo's own (unrotated) coordinates.
    var offset: CGPoint
    /// Tilt relative to the photo.
    var tilt: Angle
    var color: Color

    init(id: UUID = UUID(), photoID: BoardPhoto.ID, offset: CGPoint, tilt: Angle = .zero, color: Color = HeirloomColor.rose) {
        self.id = id
        self.photoID = photoID
        self.offset = offset
        self.tilt = tilt
        self.color = color
    }
}

/// A string tied between two pins. It has no coordinates of its own; it's drawn from wherever its pins are.
struct BoardConnection: Identifiable {
    let id: UUID
    var fromPinID: BoardPin.ID
    var toPinID: BoardPin.ID
    var color: Color
    var curve: StringCurve

    init(id: UUID = UUID(), from: BoardPin.ID, to: BoardPin.ID, color: Color = HeirloomColor.string, curve: StringCurve = .gentle) {
        self.id = id
        self.fromPinID = from
        self.toPinID = to
        self.color = color
        self.curve = curve
    }
}

@Observable
final class CorkboardModel {
    /// Width of the Figma frame that board units are measured against.
    static let designWidth: CGFloat = 435

    /// Draw order: later photos sit on top.
    var photos: [BoardPhoto]
    var pins: [BoardPin]
    var connections: [BoardConnection]

    init(photos: [BoardPhoto] = [], pins: [BoardPin] = [], connections: [BoardConnection] = []) {
        self.photos = photos
        self.pins = pins
        self.connections = connections
    }

    func photo(id: BoardPhoto.ID) -> BoardPhoto? {
        photos.first { $0.id == id }
    }

    /// The pin's attachment point on the board, following its photo's position and rotation.
    func location(of pin: BoardPin) -> CGPoint? {
        guard let photo = photo(id: pin.photoID) else { return nil }
        let radians = photo.rotation.radians
        let rotated = CGPoint(
            x: pin.offset.x * cos(radians) - pin.offset.y * sin(radians),
            y: pin.offset.x * sin(radians) + pin.offset.y * cos(radians))
        return CGPoint(x: photo.center.x + rotated.x, y: photo.center.y + rotated.y)
    }

    func tilt(of pin: BoardPin) -> Angle {
        (photo(id: pin.photoID)?.rotation ?? .zero) + pin.tilt
    }

    func endpoints(of connection: BoardConnection) -> (from: CGPoint, to: CGPoint)? {
        guard
            let fromPin = pins.first(where: { $0.id == connection.fromPinID }),
            let toPin = pins.first(where: { $0.id == connection.toPinID }),
            let from = location(of: fromPin),
            let to = location(of: toPin)
        else { return nil }
        return (from, to)
    }

    func movePhoto(_ id: BoardPhoto.ID, to center: CGPoint) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].center = center
    }

    func bringToFront(_ id: BoardPhoto.ID) {
        guard let index = photos.firstIndex(where: { $0.id == id }), index != photos.indices.last else { return }
        photos.append(photos.remove(at: index))
    }

    @discardableResult
    func connect(_ from: BoardPin.ID, to: BoardPin.ID, color: Color = HeirloomColor.string, curve: StringCurve = .gentle) -> BoardConnection {
        let connection = BoardConnection(from: from, to: to, color: color, curve: curve)
        connections.append(connection)
        return connection
    }
}

extension CorkboardModel {
    /// The layout from the Figma home mockup.
    static func sample() -> CorkboardModel {
        let left = BoardPhoto(center: CGPoint(x: 79.9, y: 213.3), rotation: .degrees(-5.11))
        let right = BoardPhoto(center: CGPoint(x: 375.5, y: 256.3), rotation: .degrees(5.94))
        let bottom = BoardPhoto(center: CGPoint(x: 214, y: 570), rotation: .degrees(-0.79))

        let bottomPin = BoardPin(photoID: bottom.id, offset: CGPoint(x: -45.6, y: -149.1), tilt: .degrees(-13.13))
        let rightPin = BoardPin(photoID: right.id, offset: CGPoint(x: 24.5, y: -135.1), tilt: .degrees(16.08))

        return CorkboardModel(
            photos: [left, right, bottom],
            pins: [bottomPin, rightPin],
            connections: [BoardConnection(from: bottomPin.id, to: rightPin.id)])
    }
}

extension CorkboardModel {
    /// The family tree: one polaroid per member, laid out in generation tiers by `CorkboardLayoutEngine`,
    /// with a pin on each photo and strings for spouse and parent–child relationships.
    static func familyTree(from members: [MemberDocument]) -> CorkboardModel {
        let card = PolaroidCard.size
        // Run the engine at the board's polaroid size so its positions come out in board units.
        let engine = CorkboardLayoutEngine(
            cardWidth: card.width,
            cardHeight: card.height,
            horizontalGap: 70,
            spouseGap: 36,
            tierHeight: card.height + 130,
            topPadding: 60,
            leftPadding: 40)
        let layout = engine.computeLayout(for: members)

        var photos: [BoardPhoto] = []
        var pinByMember: [String: BoardPin.ID] = [:]
        var pins: [BoardPin] = []
        // Stable order so the board doesn't reshuffle between refreshes.
        for node in layout.nodes.sorted(by: { ($0.position.y, $0.position.x) < ($1.position.y, $1.position.x) }) {
            let photo = BoardPhoto(
                memberId: node.member._id,
                center: CGPoint(x: node.position.x + node.size.width / 2, y: node.position.y + node.size.height / 2),
                rotation: .degrees(node.rotationDegrees),
                imageName: node.member.placeholderImageName,
                caption: node.member.name)
            photos.append(photo)

            // Pushed into the top edge of the photo, tilted a little in a direction that varies per card.
            let tilt: Angle = .degrees(node.rotationDegrees >= 0 ? -10 : 10)
            let pin = BoardPin(photoID: photo.id, offset: CGPoint(x: 0, y: -card.height / 2 + 12), tilt: tilt)
            pins.append(pin)
            pinByMember[node.member._id] = pin.id
        }

        let connections: [BoardConnection] = layout.strings.compactMap { string in
            guard let from = pinByMember[string.fromMemberId], let to = pinByMember[string.toMemberId] else { return nil }
            switch string.type {
            case .spouse:
                return BoardConnection(from: from, to: to, color: HeirloomColor.rose, curve: .init(startBend: 0.04, endBend: 0.04))
            case .parentChild, .passionConnection:
                return BoardConnection(from: from, to: to, color: HeirloomColor.string, curve: .init(startBend: 0.06, endBend: -0.06))
            }
        }

        return CorkboardModel(photos: photos, pins: pins, connections: connections)
    }
}
