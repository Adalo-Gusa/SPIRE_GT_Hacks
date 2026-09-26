import SwiftUI

/// The app shell: the board background, the selected page, and the persistent bottom bar.
struct MainTabView: View {
    /// Add an `AppTab` here (and a case in `page(for:)`) to add a page to the bar.
    private let tabs: [AppTab] = [.records, .home, .map]

    @State private var selection = AppTab.home.id
    @State private var isShowingFeed = false
    /// Kept here so the board's zoom survives tab switches and the pinch can be caught anywhere on screen.
    @State private var boardCamera = BoardCameraController()
    /// Height of the status-bar area; the board is laid out from the very top of the screen.
    @State private var topSafeArea: CGFloat = 0

    var body: some View {
        ZStack {
            CorkboardBackground()
            page(for: selection)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(tabs: tabs, selection: $selection)
                .padding(.horizontal, 13)
                .padding(.bottom, 4)
        }
        // Recognize the board's pinch over the whole screen, tab bar included, so a finger that lands on
        // the bar or a button still counts. Other tabs keep their own gestures (the map has its own pinch).
        .simultaneousGesture(boardPinch, including: selection == AppTab.home.id ? .all : .subviews)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { topSafeArea = proxy.safeAreaInsets.top }
                    .onChange(of: proxy.safeAreaInsets.top) { _, inset in topSafeArea = inset }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingFeed) {
            ContentUnavailableView("Feed", systemImage: "camera", description: Text("Family moments will show up here."))
                .foregroundStyle(HeirloomColor.plum)
                .presentationDetents([.medium, .large])
                .presentationBackground(HeirloomColor.board)
        }
    }

    private var boardPinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                // This view starts below the status bar; the board starts at the top of the screen.
                let anchor = CGPoint(x: value.startLocation.x, y: value.startLocation.y + topSafeArea)
                boardCamera.pinchChanged(magnification: value.magnification, anchor: anchor)
            }
            .onEnded { _ in boardCamera.pinchEnded() }
    }

    @ViewBuilder
    private func page(for id: AppTab.ID) -> some View {
        switch id {
        case AppTab.home.id:
            // The feed lives behind a floating camera button on the board rather than in the bar.
            HomeCorkboardView(cameraController: boardCamera) { isShowingFeed = true }
        case AppTab.records.id:
            ContentUnavailableView("Records", systemImage: "book", description: Text("Your family's recorded stories will live here."))
                .foregroundStyle(HeirloomColor.plum)
        case AppTab.map.id:
            MapGlobeView()
        default:
            ContentUnavailableView("Coming soon", systemImage: "hammer")
        }
    }
}

#Preview {
    MainTabView()
}
