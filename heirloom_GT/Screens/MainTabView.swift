import SwiftUI

/// The app shell: the board background, the selected page, and the persistent bottom bar.
struct MainTabView: View {
    /// Add an `AppTab` here (and a case in `page(for:)`) to add a page to the bar.
    private let tabs: [AppTab] = [.feed, .home, .map]

    @State private var selection = AppTab.home.id

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
    }

    @ViewBuilder
    private func page(for id: AppTab.ID) -> some View {
        switch id {
        case AppTab.home.id:
            HomeCorkboardView()
        case AppTab.feed.id:
            ContentUnavailableView("Feed", systemImage: "camera", description: Text("Family moments will show up here."))
                .foregroundStyle(HeirloomColor.plum)
        case AppTab.map.id:
            ContentUnavailableView("Map", systemImage: "mappin.and.ellipse", description: Text("See where your family's stories happened."))
                .foregroundStyle(HeirloomColor.plum)
        default:
            ContentUnavailableView("Coming soon", systemImage: "hammer")
        }
    }
}

#Preview {
    MainTabView()
}
