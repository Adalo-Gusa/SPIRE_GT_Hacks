import SwiftUI

@main
struct heirloom_GTApp: App {
    init() {
        HeirloomFont.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
