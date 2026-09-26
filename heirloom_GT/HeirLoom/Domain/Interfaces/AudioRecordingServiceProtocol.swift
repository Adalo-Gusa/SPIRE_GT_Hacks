import Foundation

enum AudioRecordingError: Error, LocalizedError {
    case permissionDenied
    case alreadyRecording
    case notRecording
    case sessionConfigurationFailed(any Error)
    case recorderFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Microphone access is required to record a story."
        case .alreadyRecording: "A recording is already in progress."
        case .notRecording: "There is no active recording to stop."
        case .sessionConfigurationFailed(let error): "Could not configure audio: \(error.localizedDescription)"
        case .recorderFailed: "The recorder failed to start."
        }
    }
}

/// Push-to-talk audio capture.
protocol AudioRecordingServiceProtocol: Sendable {
    func requestPermission() async -> Bool
    /// Begins recording and returns the file URL being written to.
    func startRecording() async throws -> URL
    func stopRecording() async throws -> (fileURL: URL, duration: TimeInterval)
    /// Stops recording and deletes the partial file.
    func cancelRecording() async
    /// Normalized input power in `0...1`, emitted roughly 20 times per second while recording.
    /// Finishes when the recording stops or is cancelled.
    func meteringStream() async -> AsyncStream<Float>
}
