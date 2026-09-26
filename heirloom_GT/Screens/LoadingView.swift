import SwiftUI

/// First screen: the board with a few pins and strings while the looped O's in the logo draw themselves.
struct LoadingView: View {
    var onFinished: () -> Void = {}

    @State private var lettersOpacity: Double = 0
    @State private var drawProgress: CGFloat = 0

    /// The Figma frame this screen was designed at.
    private static let designSize = CGSize(width: 435, height: 943)

    var body: some View {
        GeometryReader { proxy in
            let sx = proxy.size.width / Self.designSize.width
            let sy = proxy.size.height / Self.designSize.height
            let point = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * sx, y: y * sy) }

            ZStack {
                CorkboardBackground()

                BoardString(from: point(-11.6, 566.3), to: point(205.6, 520.7), curve: .loose, lineWidth: 5 * sx)
                BoardString(from: point(326.5, 180.3), to: point(474.7, 441.8), curve: .loose, lineWidth: 5 * sx)

                Pushpin(showsHole: false).pinned(at: point(109.4, 540.3), tilt: .degrees(-62.31), scale: sx)
                Pushpin(showsHole: false).pinned(at: point(259, 298.4), tilt: .degrees(58.62), scale: sx)
                Pushpin(showsHole: false).pinned(at: point(349.3, 314.9), tilt: .degrees(21.32), scale: sx)

                HeirloomLogo(drawProgress: drawProgress, lettersOpacity: lettersOpacity)
                    .frame(width: HeirloomLogo.designSize.width * sx)
                    .position(point(50 + HeirloomLogo.designSize.width / 2, 307 + HeirloomLogo.designSize.height / 2))
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinished)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Loading. Tap to skip.")
        .task {
            withAnimation(.easeOut(duration: 0.4)) { lettersOpacity = 1 }
            withAnimation(.easeInOut(duration: 1.6).delay(0.3)) { drawProgress = 1 }
            try? await Task.sleep(for: .seconds(2.6))
            onFinished()
        }
    }
}

#Preview {
    LoadingView()
}
