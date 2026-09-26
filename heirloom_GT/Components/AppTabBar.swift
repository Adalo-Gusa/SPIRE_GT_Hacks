import SwiftUI

/// One destination in the bottom bar. Add a case to the tab list to add a page.
struct AppTab: Identifiable, Hashable {
    enum Icon: Hashable {
        /// An image in the asset catalog, drawn as-is.
        case asset(String)
        /// An SF Symbol, drawn inside a plum badge to match the custom icons.
        case symbol(String)
    }

    let id: String
    var title: String
    var icon: Icon
    /// The large centered button (the yarn ball). At most one tab should be featured.
    var isFeatured = false
}

/// The persistent bottom bar. Tabs listed before the featured tab sit to its left, the rest to its right,
/// and regular tabs share the remaining width evenly, so the bar adapts to any number of tabs.
struct AppTabBar: View {
    let tabs: [AppTab]
    @Binding var selection: AppTab.ID

    var barHeight: CGFloat = 108
    var featuredDiameter: CGFloat = 176
    /// How far the featured button sits above the bar's vertical center.
    static let featuredLift: CGFloat = 10

    /// How far the featured button rises above the top of the bar.
    var featuredRise: CGFloat {
        max(0, (featuredDiameter - barHeight) / 2 + Self.featuredLift)
    }
    /// Tint laid over the glass (and over the blur on iOS versions without Liquid Glass).
    var glassTint: Color = HeirloomColor.plum.opacity(0.2)
    /// Called when the featured button is tapped while its tab is already selected (Home uses it to open Loomie).
    var onFeaturedReselect: (() -> Void)? = nil

    var body: some View {
        let featuredIndex = tabs.firstIndex(where: \.isFeatured)
        let leading = featuredIndex.map { Array(tabs[..<$0]) } ?? tabs
        let trailing = featuredIndex.map { Array(tabs[($0 + 1)...]) } ?? []

        GlassGroup {
            HStack(spacing: 0) {
                ForEach(leading) { tab in item(for: tab) }
                if featuredIndex != nil {
                    // Reserve room under the featured button (it overhangs the bar slightly).
                    Color.clear.frame(width: featuredDiameter * 0.9)
                }
                ForEach(trailing) { tab in item(for: tab) }
            }
            .padding(.horizontal, 6)
            .frame(height: barHeight)
            .frame(maxWidth: .infinity)
            .glassBackground(in: RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous), tint: glassTint)
            .overlay {
                if let featuredIndex {
                    featuredButton(for: tabs[featuredIndex])
                        .offset(y: -Self.featuredLift)
                }
            }
        }
    }

    private func item(for tab: AppTab) -> some View {
        Button {
            selection = tab.id
        } label: {
            VStack(spacing: 2) {
                icon(for: tab.icon)
                    .frame(height: 60)
                Text(tab.title)
                    .font(.heirloomDisplay(16, relativeTo: .caption))
                    .foregroundStyle(HeirloomColor.tabLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selection == tab.id ? .isSelected : [])
    }

    private func featuredButton(for tab: AppTab) -> some View {
        Button {
            if selection == tab.id {
                onFeaturedReselect?()
            } else {
                selection = tab.id
            }
        } label: {
            featuredIcon(for: tab.icon)
                .frame(width: featuredDiameter, height: featuredDiameter)
                .glassBackground(in: Circle(), tint: glassTint)
        }
        .buttonStyle(TabPressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selection == tab.id ? .isSelected : [])
    }

    @ViewBuilder
    private func icon(for icon: AppTab.Icon) -> some View {
        switch icon {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(HeirloomColor.rose)
                .frame(width: 53, height: 53)
                .background(HeirloomColor.plumMuted, in: Circle())
        }
    }
}

extension AppTabBar {
    /// The big center button's artwork. Assets (the yarn) are drawn as-is; a symbol is drawn inside a ring that
    /// echoes the yarn's, sized for the large button.
    @ViewBuilder
    fileprivate func featuredIcon(for icon: AppTab.Icon) -> some View {
        switch icon {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
        case .symbol(let name):
            ZStack {
                Circle()
                    .fill(HeirloomColor.polaroidFrame)
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(hex: 0x503650), Color(hex: 0xA57E9C)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 7)
                Image(systemName: name)
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(HeirloomColor.rose)
            }
            .padding(featuredDiameter * 0.1)
        }
    }
}

/// Groups the bar and the featured button so their Liquid Glass shapes blend into one surface.
private struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 24) { content }
        } else {
            content
        }
    }
}

private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension AppTab {
    static let records = AppTab(id: "records", title: "records", icon: .asset("TabRecords"))
    static let home = AppTab(id: "home", title: "home", icon: .asset("TabYarn"), isFeatured: true)
    static let map = AppTab(id: "map", title: "map", icon: .asset("TabMap"))
}

#Preview {
    struct Demo: View {
        @State private var selection = AppTab.home.id
        var body: some View {
            ZStack(alignment: .bottom) {
                CorkboardBackground()
                VStack(spacing: 60) {
                    AppTabBar(tabs: [.records, .home, .map], selection: $selection)
                    AppTabBar(
                        tabs: [
                            .records,
                            AppTab(id: "people", title: "people", icon: .symbol("person.2.fill")),
                            .home,
                            .map,
                            AppTab(id: "me", title: "me", icon: .symbol("person.crop.circle")),
                        ],
                        selection: $selection)
                }
                .padding(.horizontal, 13)
            }
        }
    }
    return Demo()
}

private struct TabBarTopKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// Global y of the highest point of the tab bar (the top of the yarn button), so pages can keep content
    /// clear of it. Needed because some containers, like `NavigationStack`, extend under the bar.
    var tabBarTop: CGFloat? {
        get { self[TabBarTopKey.self] }
        set { self[TabBarTopKey.self] = newValue }
    }
}
