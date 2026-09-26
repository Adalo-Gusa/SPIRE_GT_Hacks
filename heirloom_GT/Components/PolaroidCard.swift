import SwiftUI

/// A reusable polaroid-style photo. It has no built-in position; callers place, rotate and drag it.
struct PolaroidCard: View {
    var image: Image?
    var caption: String?
    var frameColor: Color = HeirloomColor.polaroidFrame
    var placeholderColor: Color = HeirloomColor.polaroidPhoto

    /// Card size from the Figma frame; the photo well is inset from the top and sides.
    static let size = CGSize(width: 211, height: 287)
    private static let photoSize = CGSize(width: 191, height: 200)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                placeholderColor
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: Self.photoSize.width, height: Self.photoSize.height)
            .clipped()
            .padding(.top, 12)

            if let caption {
                Text(caption)
                    .font(.heirloomDisplay(fixedSize: 18))
                    .foregroundStyle(HeirloomColor.tabLabel)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(frameColor)
        .compositingGroup()
        .shadow(color: .black.opacity(0.3), radius: 2, x: 6, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption ?? "Photo")
    }
}

#Preview {
    ZStack {
        CorkboardBackground()
        PolaroidCard(caption: "Grandpa's radio, 1962")
            .rotationEffect(.degrees(-5))
    }
}
