import SwiftUI

struct MainRootTabView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL
    @State private var selectedTab: AppTab = .corkboard

    var body: some View {
        TabView(selection: $selectedTab) {
            PlaceholderCorkboardView(
                viewModel: container.corkboardViewModel,
                sparkViewModel: container.sparkViewModel,
                onSparkAction: perform
            )
            .tabItem { Label("Corkboard", systemImage: "square.grid.3x3") }
            .tag(AppTab.corkboard)
            .badge(container.sparkViewModel.pendingSparks.count)

            PlaceholderLoomRecorderView(
                viewModel: container.loomVoiceViewModel,
                members: container.corkboardViewModel.graph.members
            )
            .tabItem { Label("Record", systemImage: "mic") }
            .tag(AppTab.recorder)

            PlaceholderStorybookView(viewModel: container.storybookViewModel)
                .tabItem { Label("Storybook", systemImage: "book") }
                .tag(AppTab.storybook)
        }
        .task { await container.sparkViewModel.observeSparks() }
    }

    /// Runs the spark's call-to-action and resolves it only once the action actually happened.
    private func perform(_ spark: LoomSpark) {
        let sparks = container.sparkViewModel
        switch sparks.route(for: spark) {
        case .openURL(let url):
            openURL(url) { accepted in
                Task { @MainActor in
                    if accepted {
                        await sparks.resolve(spark)
                    } else {
                        sparks.actionFailed()
                    }
                }
            }
        case .switchTab(let tab):
            selectedTab = tab
            Task { await sparks.resolve(spark) }
        case .none:
            break
        }
    }
}

#Preview {
    MainRootTabView()
        .environment(AppContainer.preview())
}
