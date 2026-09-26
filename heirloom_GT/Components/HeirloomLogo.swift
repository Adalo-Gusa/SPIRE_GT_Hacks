import SwiftUI

/// The "heir LOOM" wordmark. `drawProgress` (0...1) traces the looped O's like a pen stroke.
struct HeirloomLogo: View {
    var drawProgress: CGFloat = 1
    /// Fades in "heir", the L and the M.
    var lettersOpacity: Double = 1

    /// Size of the logo group in the Figma frame; everything below is laid out in these units.
    static let designSize = CGSize(width: 335, height: 160)

    private static let letterL = SVGPathShape(
        "M0.00151029 0H15.771V58.6275C15.771 70.8627 22.1425 73.2418 25.3282 72.902H54V91H15.771C2.96426 91 -0.0781335 78.9346 0.00151029 72.902V0Z",
        viewBox: CGSize(width: 54, height: 91))

    /// The two O's are one continuous stroke, so trimming it draws both loops in order.
    private static let loops = SVGPathShape(
        "M61 19C61 19 61.2764 10 41.7117 10C22.147 10 8.38617 30.1481 10.1525 50.3594C11.7478 68.6135 24.0417 83.9923 41.7117 83.9923C90.1313 83.9923 79.3234 10 119.961 10C142.874 10 160.706 29.4741 158.87 50.3594C157.199 69.3572 143.103 83.5751 124.717 83.9923C106.33 84.4094 106.5 70.5 106.5 70.5",
        viewBox: CGRect(x: 10, y: 10, width: 149, height: 74))

    private static let letterMParts: [SVGPathShape] = {
        let box = CGSize(width: 89.1831, height: 91.7247)
        return [
            "M57.242 24.0512H32.0667V38.5409C32.5662 42.2269 35.9029 49.6751 45.2537 49.9801C54.6046 50.2852 57.1421 42.4811 57.242 38.5409V24.0512Z",
            "M26.8491 0.235463C3.83166 -2.21682 -0.714371 15.0906 0.0848444 24.0509H19.8654C19.8654 17.2131 31.9441 18.3921 31.9441 24.0509H46.0302C48.4279 5.37583 34.2418 0.392663 26.8491 0.235463Z",
            "M62.3935 0.235463C85.4109 -2.21682 89.8967 15.0906 89.0975 24.0509H69.3169C69.3169 17.2131 57.2985 18.3921 57.2985 24.0509H43.2124C40.8147 5.37583 55.0008 0.392663 62.3935 0.235463Z",
            "M19.8656 91.7247H0.0850156V24.0512H19.8656V91.7247Z",
            "M89.0975 91.7247H69.3169V24.0512H89.0975V91.7247Z",
        ].map { SVGPathShape($0, viewBox: box) }
    }()

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.designSize.width, proxy.size.height / Self.designSize.height)
            artwork
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(Self.designSize, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("HeirLoom")
    }

    private var artwork: some View {
        ZStack(alignment: .topLeading) {
            Text("heir")
                .font(.heirloomDisplay(fixedSize: 48))
                .foregroundStyle(HeirloomColor.plum)
                .opacity(lettersOpacity)

            Group {
                Self.letterL
                    .fill(HeirloomColor.plum)
                    .frame(width: 54, height: 91)
                    .offset(x: 4, y: 67.96)
                    .opacity(lettersOpacity)

                Self.loops
                    .trim(from: 0, to: drawProgress)
                    .stroke(
                        LinearGradient(
                            colors: [HeirloomColor.plum, HeirloomColor.rose],
                            startPoint: UnitPoint(x: 0.5, y: 0),
                            endPoint: UnitPoint(x: 0.403, y: 1.534)),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
                    .frame(width: 149, height: 74)
                    .offset(x: 74, y: 76.96)

                ZStack {
                    ForEach(Self.letterMParts.indices, id: \.self) { index in
                        Self.letterMParts[index].fill(HeirloomColor.plum)
                    }
                }
                .frame(width: 89.18, height: 91.72)
                .compositingGroup() // Shadow the M as one shape, not each overlapping piece.
                .offset(x: 245.82, y: 68.2)
                .opacity(lettersOpacity)
            }
            .shadow(color: .black.opacity(0.25), radius: 2, x: 6, y: 6)
        }
        .frame(width: Self.designSize.width, height: Self.designSize.height, alignment: .topLeading)
    }
}

#Preview("Drawn") {
    ZStack {
        CorkboardBackground()
        HeirloomLogo().padding(40)
    }
}

#Preview("Animating") {
    struct Demo: View {
        @State private var progress: CGFloat = 0
        var body: some View {
            ZStack {
                CorkboardBackground()
                HeirloomLogo(drawProgress: progress).padding(40)
            }
            .onTapGesture {
                progress = 0
                withAnimation(.easeInOut(duration: 1.6)) { progress = 1 }
            }
            .task { withAnimation(.easeInOut(duration: 1.6)) { progress = 1 } }
        }
    }
    return Demo()
}
