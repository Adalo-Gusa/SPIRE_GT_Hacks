import Foundation

/// Which family member is using this phone. There are no accounts; each device just remembers who it is,
/// so two phones (or simulators) on the same database can act as different people in a demo.
///
/// Set it in the app from a member's profile ("This is me"), or at launch with the argument
/// `-currentMemberId member_grandpa_joe` (Xcode: Edit Scheme → Run → Arguments), which overrides the saved choice.
enum CurrentUser {
    /// UserDefaults key; views read it with `@AppStorage(CurrentUser.defaultsKey)`.
    static let defaultsKey = "currentMemberId"
    static let defaultMemberId = "member_alex"

    static var memberId: String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? defaultMemberId
    }
}
