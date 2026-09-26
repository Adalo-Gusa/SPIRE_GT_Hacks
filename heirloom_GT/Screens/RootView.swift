import SwiftUI

/// Shows the loading screen first, then fades to the main app.
struct RootView: View {
    @State private var isLoading = true

    var body: some View {
        ZStack {
            MainTabView()
            if isLoading {
                LoadingView {
                    withAnimation(.easeInOut(duration: 0.5)) { isLoading = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}

#Preview {
    RootView()
}
