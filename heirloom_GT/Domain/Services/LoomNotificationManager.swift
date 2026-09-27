import Foundation
import UserNotifications

/// Routes triggered by tapping a local notification or actionable notification button.
enum NotificationRoute: Equatable {
    /// Opens Loomie chat on Home and instructs her to ask this opening question immediately.
    case loomiPrompt(prompt: String)
    /// Opens the Intergenerational Spark Sheet for a detected family connection.
    case spark(spark: SparkDocument)
    /// Prompts a phone call or FaceTime with the specified family member.
    case callMember(name: String, phone: String?)
}

/// Manages interactive notifications for intergenerational connection sparks and
/// periodic Loomie biographical memory prompts with direct deep-linking into voice chat.
@MainActor
final class LoomNotificationManager: NSObject, ObservableObject {
    static let shared = LoomNotificationManager()

    @Published var pendingRoute: NotificationRoute?

    // Category & Action Identifiers
    private enum Category {
        static let spark = "HEIRLOOM_SPARK_CATEGORY"
        static let prompt = "HEIRLOOM_PROMPT_CATEGORY"
    }

    private enum Action {
        static let callMember = "ACTION_CALL_MEMBER"
        static let talkLoomie = "ACTION_TALK_LOOMIE"
        static let viewStory = "ACTION_VIEW_STORY"
        static let answerPrompt = "ACTION_ANSWER_PROMPT"
    }

    // Curated Pool of Warm Biographical Questions
    private static let curatedPrompts: [String] = [
        "What was your favorite homemade meal or recipe growing up, and who made it?",
        "What's a piece of advice from your parents or grandparents that you've never forgotten?",
        "What was your very first job, and what did you spend your first paycheck on?",
        "How did your parents (or you and your spouse) first cross paths?",
        "What was a family holiday tradition that felt truly magical when you were young?",
        "What song, sound, or smell instantly takes you back to your childhood home?",
        "What was the most adventurous road trip or vacation your family ever took?",
        "Who was the funniest or most colorful storyteller in your extended family?",
        "What was a beloved family heirloom or keepsake that was passed down to you?",
        "What is one family memory you hope the next generation will always carry forward?"
    ]

    private override init() {
        super.init()
    }

    // MARK: - Authorization & Categories

    /// Requests notification permissions from the user and registers interactive action categories.
    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[LoomNotificationManager] Authorization error: \(error.localizedDescription)")
            } else {
                print("[LoomNotificationManager] Notifications authorized: \(granted)")
            }
        }

        registerCategories()
    }

    private func registerCategories() {
        let center = UNUserNotificationCenter.current()

        // 1. Spark Connection Actions
        let callAction = UNNotificationAction(
            identifier: Action.callMember,
            title: "📞 Give a Call",
            options: [.foreground]
        )
        let talkLoomieAction = UNNotificationAction(
            identifier: Action.talkLoomie,
            title: "🧵 Ask Loomie",
            options: [.foreground]
        )
        let sparkCategory = UNNotificationCategory(
            identifier: Category.spark,
            actions: [callAction, talkLoomieAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // 2. Loomie Question Prompt Actions
        let answerAction = UNNotificationAction(
            identifier: Action.answerPrompt,
            title: "🎙️ Answer Loomie",
            options: [.foreground]
        )
        let promptCategory = UNNotificationCategory(
            identifier: Category.prompt,
            actions: [answerAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([sparkCategory, promptCategory])
    }

    // MARK: - Scheduling Notifications

    /// Schedules an intergenerational spark alert when the archiving agent uncovers a connection.
    func scheduleSparkNotification(_ spark: SparkDocument, elderName: String = "Grandpa Joe", targetName: String = "Alex", delaySeconds: Double = 1.0) {
        let content = UNMutableNotificationContent()
        content.title = "⚡ Family Spark on \(spark.matchedPassion)"
        content.subtitle = "\(elderName) & \(targetName)"
        content.body = "\(spark.sparkMessage) \(spark.ctaAction)"
        content.sound = .default
        content.categoryIdentifier = Category.spark

        // Encode spark payload for deep-linking
        var userInfo: [String: Any] = [
            "spark_id": spark._id,
            "elder_id": spark.elderId,
            "target_member_id": spark.targetMemberId,
            "elder_name": elderName,
            "target_name": targetName,
            "matched_passion": spark.matchedPassion,
            "spark_message": spark.sparkMessage,
            "cta_action": spark.ctaAction
        ]
        if let json = try? JSONEncoder().encode(spark),
           let str = String(data: json, encoding: .utf8) {
            userInfo["spark_json"] = str
        }
        content.userInfo = userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1.0, delaySeconds), repeats: false)
        let request = UNNotificationRequest(identifier: "spark_\(spark._id)_\(UUID().uuidString.prefix(4))", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[LoomNotificationManager] Failed to schedule spark notification: \(error.localizedDescription)")
            } else {
                print("[LoomNotificationManager] Scheduled Spark notification in \(delaySeconds)s: '\(spark.matchedPassion)'")
            }
        }
    }

    /// Schedules a recurring or one-off Loomie conversational prompt to collect more family lore.
    func schedulePromptNotification(prompt: String? = nil, delaySeconds: Double = 1.0) {
        let question = prompt ?? Self.curatedPrompts.randomElement() ?? Self.curatedPrompts[0]

        let content = UNMutableNotificationContent()
        content.title = "🧵 Question from Loomie"
        content.body = question
        content.sound = .default
        content.categoryIdentifier = Category.prompt
        content.userInfo = [
            "prompt_text": question
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1.0, delaySeconds), repeats: false)
        let request = UNNotificationRequest(identifier: "loomi_prompt_\(UUID().uuidString.prefix(6))", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[LoomNotificationManager] Failed to schedule prompt notification: \(error.localizedDescription)")
            } else {
                print("[LoomNotificationManager] Scheduled Loomie prompt notification in \(delaySeconds)s: '\(question)'")
            }
        }
    }

    /// Sets up periodic background triggers (e.g. every 3 days) to gently engage the family.
    func setupPeriodicPrompts(intervalDays: Int = 3) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["periodic_loomi_prompt"])

        let content = UNMutableNotificationContent()
        content.title = "🧵 Time for a Family Memory"
        content.body = "Loomie has a new question for your family archive. Tap to share a quick story."
        content.sound = .default
        content.categoryIdentifier = Category.prompt
        content.userInfo = [
            "prompt_text": Self.curatedPrompts.randomElement() ?? Self.curatedPrompts[0]
        ]

        let intervalSeconds = Double(intervalDays * 24 * 60 * 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: intervalSeconds, repeats: true)
        let request = UNNotificationRequest(identifier: "periodic_loomi_prompt", content: content, trigger: trigger)

        center.add(request)
    }

    // MARK: - Testing & Demo Helpers

    /// Simulates a real intergenerational Spark connection notification after a brief delay.
    func simulateSparkNotification(delaySeconds: Double = 3.0, archive: FamilyArchive? = nil) {
        let elder = archive?.members.first(where: { $0._id == "member_grandpa_joe" })?.name ?? "Grandpa Joe"
        let target = archive?.members.first(where: { $0._id == "member_alex_clarke" })?.name ?? "Alex"

        let spark = SparkDocument(
            id: "spark_electronics_\(UUID().uuidString.prefix(6))",
            familyId: AppConfiguration.mongoDBFamilyId,
            elderId: "member_grandpa_joe",
            targetMemberId: "member_alex_clarke",
            matchedPassion: "Electronics",
            sparkMessage: "Grandpa Joe just recorded a memory about building shortwave radios from scrap parts in 1958. It reminded us of your latest Arduino projects!",
            ctaAction: "Would you like to give Grandpa Joe a call?",
            isRead: false
        )

        scheduleSparkNotification(spark, elderName: elder, targetName: target, delaySeconds: delaySeconds)
    }

    /// Simulates a Loomie prompt notification after a brief delay.
    func simulatePromptNotification(delaySeconds: Double = 3.0) {
        let question = Self.curatedPrompts.randomElement() ?? Self.curatedPrompts[0]
        schedulePromptNotification(prompt: question, delaySeconds: delaySeconds)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension LoomNotificationManager: UNUserNotificationCenterDelegate {
    /// Present notification banners even when the app is currently in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle user interaction when tapping the notification or its action buttons.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier
        let categoryId = response.notification.request.content.categoryIdentifier

        Task { @MainActor in
            if categoryId == Category.prompt || userInfo["prompt_text"] != nil {
                let prompt = (userInfo["prompt_text"] as? String) ?? "What is a family story you've always treasured?"
                self.pendingRoute = .loomiPrompt(prompt: prompt)
            } else if categoryId == Category.spark || userInfo["spark_id"] != nil {
                let elderName = (userInfo["elder_name"] as? String) ?? "Grandpa Joe"
                let passion = (userInfo["matched_passion"] as? String) ?? "Family Memory"

                switch actionId {
                case Action.callMember:
                    self.pendingRoute = .callMember(name: elderName, phone: nil)

                case Action.talkLoomie:
                    let prompt = "Loomie, tell me more about \(elderName)'s story on \(passion)."
                    self.pendingRoute = .loomiPrompt(prompt: prompt)

                default:
                    // Default tap on the notification banner opens the Spark Sheet
                    if let jsonStr = userInfo["spark_json"] as? String,
                       let data = jsonStr.data(using: .utf8),
                       let doc = try? JSONDecoder().decode(SparkDocument.self, from: data) {
                        self.pendingRoute = .spark(spark: doc)
                    } else {
                        let doc = SparkDocument(
                            id: (userInfo["spark_id"] as? String) ?? "spark_alert",
                            familyId: AppConfiguration.mongoDBFamilyId,
                            elderId: (userInfo["elder_id"] as? String) ?? "member_grandpa_joe",
                            targetMemberId: (userInfo["target_member_id"] as? String) ?? "member_alex_clarke",
                            matchedPassion: passion,
                            sparkMessage: (userInfo["spark_message"] as? String) ?? "A shared connection was detected.",
                            ctaAction: (userInfo["cta_action"] as? String) ?? "Would you like to give \(elderName) a call?"
                        )
                        self.pendingRoute = .spark(spark: doc)
                    }
                }
            }

            completionHandler()
        }
    }
}
