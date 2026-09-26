import Foundation
import os
@preconcurrency import Speech

/// On-device file transcription with `SFSpeechRecognizer`. Audio stays on the device when the
/// recognizer supports on-device recognition for the locale.
final class SpeechTranscriptionService: TranscriptionServiceProtocol {
    private let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func transcribe(audioAt url: URL) async throws -> String {
        guard await Self.requestAuthorization() else { throw TranscriptionError.permissionDenied }
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // The recognizer must outlive its recognition task.
        defer { withExtendedLifetime(recognizer) {} }

        let state = OSAllocatedUnfairLock(uncheckedState: RecognitionState())
        let transcript: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Error>) in
                let task = recognizer.recognitionTask(with: request) { result, error in
                    let outcome: Result<String, any Error>
                    if let result, result.isFinal {
                        outcome = .success(result.bestTranscription.formattedString)
                    } else if let error {
                        outcome = .failure(error)
                    } else {
                        return
                    }
                    // The handler can fire again after the final result; resume exactly once.
                    let shouldResume = state.withLockUnchecked { current in
                        guard !current.resumed else { return false }
                        current.resumed = true
                        current.task = nil
                        return true
                    }
                    if shouldResume {
                        continuation.resume(with: outcome)
                    }
                }
                let alreadyCancelled = state.withLockUnchecked { current in
                    current.task = task
                    return current.cancelled
                }
                if alreadyCancelled {
                    task.cancel()
                }
            }
        } onCancel: {
            state.withLockUnchecked { current in
                current.cancelled = true
                current.task?.cancel()
            }
        }

        try Task.checkCancellation()
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.noSpeech }
        return trimmed
    }

    private static func requestAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

private struct RecognitionState {
    var task: SFSpeechRecognitionTask?
    var resumed = false
    var cancelled = false
}
