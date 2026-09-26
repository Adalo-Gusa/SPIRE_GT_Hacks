import Foundation
import Observation

enum AppTab: Hashable, Sendable {
    case corkboard
    case recorder
    case storybook
}

/// What the view should do after a spark's call-to-action is tapped.
enum SparkRoute: Equatable, Sendable {
    case openURL(URL)
    case switchTab(AppTab)
    case none
}

/// Pending intergenerational sparks for the device owner, and resolution of their call-to-action.
@MainActor
@Observable
final class SparkNotificationViewModel {
    private(set) var graph: FamilyGraph = .empty
    private(set) var errorMessage: String?

    let activeMemberID: UUID
    private let repository: any FamilyGraphRepositoryProtocol

    init(repository: any FamilyGraphRepositoryProtocol, activeMemberID: UUID) {
        self.repository = repository
        self.activeMemberID = activeMemberID
    }

    var pendingSparks: [LoomSpark] {
        graph.pendingSparks(for: activeMemberID)
    }

    func elder(for spark: LoomSpark) -> FamilyMember? {
        graph.member(id: spark.elderID)
    }

    /// Mirrors repository updates until the calling task is cancelled. Call from `.task`.
    func observeSparks() async {
        for await snapshot in await repository.graphUpdates() {
            graph = snapshot
        }
    }

    /// Where the spark's call-to-action leads. Does not resolve the spark; the view calls `resolve`
    /// once the action actually happened (for example, after the system accepts the `tel:` URL).
    func route(for spark: LoomSpark) -> SparkRoute {
        switch spark.actionType {
        case .callPhone:
            let digits = elder(for: spark)?.phoneNumber?.filter { $0.isNumber || $0 == "+" }
            guard let digits, !digits.isEmpty, let url = URL(string: "tel:\(digits)") else {
                errorMessage = "No phone number on file for this family member."
                return .none
            }
            return .openURL(url)
        case .sendVoiceNote:
            return .switchTab(.recorder)
        case .viewStory:
            return .switchTab(.storybook)
        }
    }

    func dismiss(_ spark: LoomSpark) async {
        await resolve(spark)
    }

    func actionFailed() {
        errorMessage = "Couldn't start that call on this device."
    }

    func resolve(_ spark: LoomSpark) async {
        do {
            try await repository.resolveSpark(id: spark.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
