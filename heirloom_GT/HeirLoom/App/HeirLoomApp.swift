import SwiftUI

@main
struct HeirLoomApp: App {
    @State private var container = AppContainer(configuration: .current())

    var body: some Scene {
        WindowGroup {
            MainRootTabView()
                .environment(container)
        }
    }
}
