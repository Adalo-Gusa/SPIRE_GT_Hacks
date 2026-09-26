import SwiftUI

/// How far a string bows away from the straight line between its ends, as fractions of its length.
/// Positive values bow to the right of the direction of travel (from → to). Opposite signs make an S-curve.
/// `sag` and `wiggle` make it hang and wander like slack twine rather than a taut line.
struct StringCurve: Hashable {
    var startBend: CGFloat
    var endBend: CGFloat
    /// How far the middle droops toward the bottom of the screen, as a fraction of the string's length.
    var sag: CGFloat = 0
    /// How far the string wanders from side to side, as a fraction of its length. Fades out toward the pins.
    var wiggle: CGFloat = 0
    /// How many side-to-side waves run along the string.
    var waves: CGFloat = 1.5
    /// Where the waves start, in radians; vary it so neighboring strings don't wander in step.
    var phase: CGFloat = 0

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
        guard curve.sag != 0 || curve.wiggle != 0 else {
            path.addCurve(to: to, control1: control1, control2: control2)
            return path
        }

        // Walk the bowed curve, pulling each point down by the sag and sideways by the wiggle (both zero at
        // the pins), then run a smooth curve through the points.
        let samples = 24
        let points = (0...samples).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(samples)
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            let base = CGPoint(
                x: a * from.x + b * control1.x + c * control2.x + d * to.x,
                y: a * from.y + b * control1.y + c * control2.y + d * to.y)
            let droop = 4 * t * u * curve.sag * length
            let wander = sin(.pi * t) * sin(2 * .pi * curve.waves * t + curve.phase) * curve.wiggle * length
            return CGPoint(x: base.x + nx * wander, y: base.y + ny * wander + droop)
        }
        addSmoothCurve(through: points, to: &path)
        return path
    }

    /// Catmull–Rom spline through `points` (already started at the first one), as cubic Béziers.
    private func addSmoothCurve(through points: [CGPoint], to path: inout Path) {
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
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
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
