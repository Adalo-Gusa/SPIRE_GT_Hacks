import Foundation

enum TranscriptionError: Error, LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Speech recognition access is required to save a story."
        case .recognizerUnavailable: "Speech recognition isn't available right now."
        case .noSpeech: "I couldn't hear a story in that recording."
        }
    }
}

/// Turns a finished recording into text.
protocol TranscriptionServiceProtocol: Sendable {
    /// Returns a non-empty transcript or throws. Never returns placeholder text.
    func transcribe(audioAt url: URL) async throws -> String
}
