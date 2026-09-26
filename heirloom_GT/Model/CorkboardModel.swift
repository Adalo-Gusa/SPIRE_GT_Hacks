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

/// A pin stuck into a photo, where it rides along when the photo moves or rotates, or straight into the board.
struct BoardPin: Identifiable {
    let id: UUID
    /// The photo the pin is stuck into; nil for a pin in the bare board.
    var photoID: BoardPhoto.ID?
    /// Where the pin sits relative to the photo's center, in the photo's own (unrotated) coordinates.
    /// For a pin in the bare board, its position on the board.
    var offset: CGPoint
    /// Tilt relative to the photo.
    var tilt: Angle
    var color: Color

    init(id: UUID = UUID(), photoID: BoardPhoto.ID?, offset: CGPoint, tilt: Angle = .zero, color: Color = HeirloomColor.rose) {
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
        guard let photoID = pin.photoID else { return pin.offset }
        guard let photo = photo(id: photoID) else { return nil }
        let radians = photo.rotation.radians
        let rotated = CGPoint(
            x: pin.offset.x * cos(radians) - pin.offset.y * sin(radians),
            y: pin.offset.x * sin(radians) + pin.offset.y * cos(radians))
        return CGPoint(x: photo.center.x + rotated.x, y: photo.center.y + rotated.y)
    }

    func tilt(of pin: BoardPin) -> Angle {
        (pin.photoID.flatMap(photo(id:))?.rotation ?? .zero) + pin.tilt
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
    /// with a pin on each photo, a pin between each couple, and slack strings for spouse and parent–child relationships.
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

        let board = CorkboardModel(photos: photos, pins: pins)

        // Each couple's string drapes into a pin in the bare board between them; their children hang from it.
        var couplePin: [String: BoardPin.ID] = [:]
        for string in layout.strings where string.type == .spouse {
            guard let a = pinByMember[string.fromMemberId], let b = pinByMember[string.toMemberId],
                  let from = board.pins.first(where: { $0.id == a }).flatMap(board.location(of:)),
                  let to = board.pins.first(where: { $0.id == b }).flatMap(board.location(of:))
            else { continue }
            let key = coupleKey(string.fromMemberId, string.toMemberId)
            let middle = BoardPin(photoID: nil, offset: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 + 34))
            board.pins.append(middle)
            couplePin[key] = middle.id
            board.connect(a, to: middle.id, color: HeirloomColor.rose, curve: twine(key + "a", sag: 0.1, wiggle: 0.012))
            board.connect(middle.id, to: b, color: HeirloomColor.rose, curve: twine(key + "b", sag: 0.1, wiggle: 0.012))
        }

        // One string per child from their parents' couple pin; otherwise one from each parent's own photo.
        var parentsByChild: [String: [String]] = [:]
        for string in layout.strings where string.type == .parentChild {
            parentsByChild[string.toMemberId, default: []].append(string.fromMemberId)
        }
        for (child, parents) in parentsByChild.sorted(by: { $0.key < $1.key }) {
            guard let childPin = pinByMember[child] else { continue }
            if parents.count == 2, let couple = couplePin[coupleKey(parents[0], parents[1])] {
                board.connect(couple, to: childPin, curve: twine(child, sag: 0.03, wiggle: 0.035))
            } else {
                for parent in parents.sorted() {
                    guard let parentPin = pinByMember[parent] else { continue }
                    board.connect(parentPin, to: childPin, curve: twine(parent + child, sag: 0.03, wiggle: 0.035))
                }
            }
        }

        for string in layout.strings where string.type == .passionConnection {
            guard let from = pinByMember[string.fromMemberId], let to = pinByMember[string.toMemberId] else { continue }
            board.connect(from, to: to, curve: twine(string.id, sag: 0.03, wiggle: 0.035))
        }

        return board
    }

    private static func coupleKey(_ a: String, _ b: String) -> String {
        [a, b].sorted().joined(separator: "+")
    }

    /// A slack, gently wandering string whose bends are picked from `key`, so each string has its own shape
    /// and keeps it across refreshes.
    private static func twine(_ key: String, sag: CGFloat, wiggle: CGFloat) -> StringCurve {
        // FNV-1a: Swift's `hashValue` changes every launch.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        let unit = { (shift: UInt64) in CGFloat((hash >> shift) & 0xffff) / 0xffff }
        let bend = (unit(0) - 0.5) * 0.12
        return StringCurve(
            startBend: bend,
            endBend: -bend * 0.6,
            sag: sag,
            wiggle: wiggle * (0.7 + 0.6 * unit(16)),
            waves: 1 + unit(32),
            phase: unit(48) * 2 * .pi)
    }
}
