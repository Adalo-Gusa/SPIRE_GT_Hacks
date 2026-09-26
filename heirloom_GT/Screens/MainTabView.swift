import SwiftUI

/// The app shell: the board background, the selected page, and the persistent bottom bar.
struct MainTabView: View {
    /// Add an `AppTab` here (and a case in `page(for:)`) to add a page to the bar.
    /// The center button shows the yarn on Home (tap it to talk to Loomie) and a family-tree icon elsewhere
    /// (tap it to go back Home).
    private var tabs: [AppTab] {
        let home = selection == AppTab.home.id
            ? AppTab(id: AppTab.home.id, title: "Talk to Loomie", icon: .asset("TabYarn"), isFeatured: true)
            : AppTab(id: AppTab.home.id, title: "Family tree", icon: .symbol("person.3.sequence.fill"), isFeatured: true)
        return [.records, home, .map]
    }

    @State private var selection = AppTab.home.id
    @State private var isShowingFeed = false
    /// Kept here so the board's zoom survives tab switches and the pinch can be caught anywhere on screen.
    @State private var boardCamera = BoardCameraController()
    /// Height of the status-bar area; the board is laid out from the very top of the screen.
    @State private var topSafeArea: CGFloat = 0
    /// Global y of the top of the tab bar's yarn button, shared with pages through the environment.
    @State private var tabBarTop: CGFloat?

    /// Members, stories and places shared by every page.
    @StateObject private var archive = FamilyArchive()
    @StateObject private var loomie = LoomieChatController()
    @State private var isChatOpen = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            CorkboardBackground()
            // All pages sit side by side on one strip, in tab-bar order, and the strip slides to the selected
            // one, so switching tabs pans across a single connected canvas. Pages stay alive while offscreen.
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        let isSelected = tab.id == selection
                        page(for: tab.id)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            // Keep each page inside its own column (the board's photos run past its edges).
                            .clipShape(ColumnClip())
                            .allowsHitTesting(isSelected)
                            .accessibilityHidden(!isSelected)
                    }
                }
                .offset(x: -CGFloat(selectedIndex) * proxy.size.width)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            }
            .environment(\.tabBarTop, tabBarTop)

            // Loomie chats over the Home board only, above the page and below the tab bar.
            if isChatOpen && selection == AppTab.home.id {
                LoomieChatOverlay(controller: loomie) { closeChat() }
                    .environment(\.tabBarTop, tabBarTop)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task { await archive.refresh() }
        .onChange(of: selection) { _, newSelection in
            if newSelection != AppTab.home.id { closeChat() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let bar = AppTabBar(tabs: tabs, selection: slidingSelection) {
                // The yarn toggles Loomie while on Home.
                if isChatOpen { closeChat() } else { openChat() }
            }
            bar
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { barTop in
                    tabBarTop = barTop - bar.featuredRise
                }
                .padding(.horizontal, 13)
                .padding(.bottom, 4)
        }
        // Recognize the board's pinch over the whole screen, tab bar included, so a finger that lands on
        // the bar or a button still counts. Other tabs keep their own gestures (the map has its own pinch).
        .simultaneousGesture(boardPinch, including: selection == AppTab.home.id && !isChatOpen ? .all : .subviews)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { topSafeArea = proxy.safeAreaInsets.top }
                    .onChange(of: proxy.safeAreaInsets.top) { _, inset in topSafeArea = inset }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingFeed) {
            FamilyFeedView()
                .presentationDetents([.medium, .large])
                .presentationBackground(HeirloomColor.board)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await LoomOrchestrator.shared.processPendingSharedPosts(archive: archive)
                }
            }
        }
        .onOpenURL { url in
            if url.scheme == "heirloom" {
                Task {
                    await LoomOrchestrator.shared.processPendingSharedPosts(archive: archive)
                    if url.host == "shared-post" || url.host == "feed" {
                        isShowingFeed = true
                    }
                }
            }
        }
        // Last, so the feed sheet presented above gets the archive too (a sheet only sees the environment
        // from where it's attached; without it, the feed crashes the moment it opens).
        .environmentObject(archive)
    }

    private func openChat() {
        withAnimation(.easeInOut(duration: 0.25)) { isChatOpen = true }
    }

    private func closeChat() {
        loomie.end()
        withAnimation(.easeInOut(duration: 0.25)) { isChatOpen = false }
    }

    private var selectedIndex: Int {
        tabs.firstIndex { $0.id == selection } ?? 0
    }

    /// Tab selection that animates the strip sliding over to the chosen page.
    private var slidingSelection: Binding<AppTab.ID> {
        Binding {
            selection
        } set: { newSelection in
            guard newSelection != selection else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                selection = newSelection
            }
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
            RecordsView()
        case AppTab.map.id:
            // The globe keeps rendering while it's alive, so it only exists while its tab is selected.
            if selection == AppTab.map.id {
                MapGlobeView(places: archive.places)
            }
        default:
            ContentUnavailableView("Coming soon", systemImage: "hammer")
        }
    }
}

/// Clips a page to its width only, so backgrounds can still extend under the status bar and home indicator.
private struct ColumnClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - 2000, width: rect.width, height: rect.height + 4000))
    }
}

#Preview {
    MainTabView()
}
