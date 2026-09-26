import SwiftUI

/// How far a string bows away from the straight line between its ends, as fractions of its length.
/// Positive values bow to the right of the direction of travel (from → to). Opposite signs make an S-curve.
struct StringCurve: Hashable {
    var startBend: CGFloat
    var endBend: CGFloat

    static let straight = StringCurve(startBend: 0, endBend: 0)
    /// The gentle arc used between photos on the home board.
    static let gentle = StringCurve(startBend: 0.08, endBend: 0.19)
    /// The loose S-curve used for decorative strings on the loading screen.
    static let loose = StringCurve(startBend: 0.3, endBend: -0.08)
}

/// A curve between two points, recomputed whenever either point moves.
struct BoardStringShape: Shape {
    var from: CGPoint
    var to: CGPoint
    var curve: StringCurve = .gentle

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(from.x, from.y), .init(to.x, to.y)) }
        set {
            from = CGPoint(x: newValue.first.first, y: newValue.first.second)
            to = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = max(hypot(dx, dy), 0.001)
        // Unit normal pointing to the right of from → to in screen coordinates.
        let nx = -dy / length, ny = dx / length

        let control1 = CGPoint(
            x: from.x + dx / 3 + nx * length * curve.startBend,
            y: from.y + dy / 3 + ny * length * curve.startBend)
        let control2 = CGPoint(
            x: from.x + dx * 2 / 3 + nx * length * curve.endBend,
            y: from.y + dy * 2 / 3 + ny * length * curve.endBend)

        var path = Path()
        path.move(to: from)
        path.addCurve(to: to, control1: control1, control2: control2)
        return path
    }
}

/// A recolorable string stretched between two points (usually two pins).
struct BoardString: View {
    var from: CGPoint
    var to: CGPoint
    var color: Color = HeirloomColor.string
    var curve: StringCurve = .gentle
    var lineWidth: CGFloat = 5

    var body: some View {
        BoardStringShape(from: from, to: to, curve: curve)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
