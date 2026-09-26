import Foundation

/// Runtime configuration. Each value is read from the scheme's environment variables first, then from
/// Info.plist, then falls back to a default. Provider credentials (Grok, Backboard, MongoDB) live only on
/// the middleware; the app holds a revocable middleware token.
struct AppConfiguration: Sendable {
    /// When true, everything runs offline against `MockDataService`. Live mode never substitutes mock data.
    var isMockMode: Bool
    var mockLatency: Duration

    /// Base URL of the HeirLoom FastAPI middleware (`HEIRLOOM_MIDDLEWARE_URL`).
    var middlewareBaseURL: URL
    /// Bearer token the middleware checks (`HEIRLOOM_API_TOKEN`). Revocable; never a provider key.
    var middlewareToken: String

    /// The family member who owns this device and receives sparks.
    var activeMemberID: UUID
    /// Default author for new recordings.
    var defaultStorytellerID: UUID

    static func current(processInfo: ProcessInfo = .processInfo, bundle: Bundle = .main) -> AppConfiguration {
        func value(_ key: String) -> String? {
            let raw = processInfo.environment[key] ?? (bundle.object(forInfoDictionaryKey: key) as? String)
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }

        func flag(_ key: String) -> Bool? {
            value(key).map { ["1", "true", "yes"].contains($0.lowercased()) }
        }

        let latencyMilliseconds = value("HEIRLOOM_MOCK_LATENCY_MS").flatMap(Int.init) ?? 600

        return AppConfiguration(
            isMockMode: flag("HEIRLOOM_MOCK_MODE") ?? true,
            mockLatency: .milliseconds(max(latencyMilliseconds, 0)),
            middlewareBaseURL: value("HEIRLOOM_MIDDLEWARE_URL").flatMap(URL.init(string:)) ?? URL(string: "http://localhost:8000")!,
            middlewareToken: value("HEIRLOOM_API_TOKEN") ?? "",
            activeMemberID: value("HEIRLOOM_ACTIVE_MEMBER_ID").flatMap(UUID.init(uuidString:)) ?? MockIDs.alex,
            defaultStorytellerID: value("HEIRLOOM_STORYTELLER_ID").flatMap(UUID.init(uuidString:)) ?? MockIDs.joseph
        )
    }

    /// Offline configuration with no artificial latency, for previews and tests.
    static var preview: AppConfiguration {
        var configuration = current()
        configuration.isMockMode = true
        configuration.mockLatency = .zero
        return configuration
    }
}
