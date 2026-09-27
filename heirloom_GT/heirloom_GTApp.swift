import SwiftUI

@main
struct heirloom_GTApp: App {
    init() {
        HeirloomFont.registerBundledFonts()
        LoomNotificationManager.shared.requestAuthorization()
        LoomNotificationManager.shared.setupPeriodicPrompts(intervalDays: 3)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
