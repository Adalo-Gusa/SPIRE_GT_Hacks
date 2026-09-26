import SwiftUI

/// A recolorable pushpin drawn from the Figma "pushpin" vector.
struct Pushpin: View {
    var color: Color = HeirloomColor.rose
    /// Draws the small shadow where the needle enters the board.
    var showsHole: Bool = true

    static let size = CGSize(width: 47.1958, height: 96.0167)
    /// Where the head meets the needle; strings attach here and the pin tilts around it.
    static let anchor = UnitPoint(x: 25.5 / size.width, y: 58.5 / size.height)

    private static let needleOuter = SVGPathShape(
        "M23.9006 92.5362C21.2758 91.8855 19.5072 89.3956 19.5072 89.3956V42.8605H28.9463V89.3956C28.9463 89.3956 26.5254 93.1868 23.9006 92.5362Z",
        viewBox: size)
    private static let needleInner = SVGPathShape(
        "M24.2259 91.2238L21.395 89.3956V42.8605H27.0585V89.3956L24.2259 91.2238Z",
        viewBox: size)
    private static let head = SVGPathShape(
        "M47.1958 58.5228H3.77566C3.77566 47.9225 10.6977 41.5917 14.1587 39.7514V5.52103H0V0H47.1958V5.52103H33.0371V39.7514C40.5884 42.4014 45.6226 53.3699 47.1958 58.5228Z",
        viewBox: size)
    private static let stemHighlight = SVGPathShape(
        "M26.4298 10.3831V35.8689L30.2054 38.7006V10.3831H26.4298Z",
        viewBox: size)
    private static let baseHighlight = SVGPathShape(
        "M38.7005 52.8593C39.4556 50.5939 35.8687 48.1397 33.9809 47.1958V52.8593H38.7005Z",
        viewBox: size)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsHole {
                Ellipse()
                    .fill(RadialGradient(
                        colors: [Color(hex: 0x7D5C39), Color(hex: 0xD7C4B0)],
                        center: .center, startRadius: 0, endRadius: 7.5))
                    .frame(width: 15.03, height: 11.56)
                    .rotationEffect(.degrees(13.92))
                    .position(x: 25.08, y: 88.6)
            }
            Self.needleOuter.fill(Color(hex: 0xB3B3B3))
            Self.needleInner.fill(Color(hex: 0xC5C5C5))
            Self.head.fill(color)
            // Highlights are a white wash so they follow whatever head color is chosen.
            Self.stemHighlight.fill(.white.opacity(0.25))
            Self.baseHighlight.fill(.white.opacity(0.25))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .compositingGroup()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Places a pushpin so its `Pushpin.anchor` sits exactly on `point`, tilted and scaled around that anchor.
    func pinned(at point: CGPoint, tilt: Angle, scale: CGFloat = 1) -> some View {
        let size = Pushpin.size
        let anchor = Pushpin.anchor
        return self
            .scaleEffect(scale, anchor: anchor)
            .rotationEffect(tilt, anchor: anchor)
            .shadow(color: .black.opacity(0.25), radius: 2 * scale, x: 6 * scale, y: 4 * scale)
            .position(
                x: point.x + (0.5 - anchor.x) * size.width,
                y: point.y + (0.5 - anchor.y) * size.height)
    }
}

#Preview {
    ZStack {
        CorkboardBackground()
        HStack(spacing: 40) {
            Pushpin()
            Pushpin(color: .teal)
            Pushpin(color: .orange).rotationEffect(.degrees(20))
        }
    }
}
