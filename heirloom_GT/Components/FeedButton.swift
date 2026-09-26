import SwiftUI

/// The camera-with-sparkle button that opens the family feed.
struct FeedButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("FeedButton")
                .resizable()
                .scaledToFit()
                .frame(width: 89, height: 82)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Feed")
    }
}
