import AVFoundation
import Foundation

/// `AVAudioRecorder`-backed push-to-talk capture. The recorder never leaves the actor, which keeps it
/// safe under Swift 6 strict concurrency even though AVFoundation types are not `Sendable`.
actor AudioRecorderService: AudioRecordingServiceProtocol {
    private static let meteringInterval: Duration = .milliseconds(50)
    private static let silenceFloorDecibels: Float = -60

    private var recorder: AVAudioRecorder?
    private var meteringTask: Task<Void, Never>?
    private var meteringContinuation: AsyncStream<Float>.Continuation?
    /// Set when an audio interruption stopped capture; the file is kept until `stopRecording` collects it.
    private var interruptedDuration: TimeInterval?
    private var interruptionObserver: (any NSObjectProtocol)?

    init() {}

    // MARK: - AudioRecordingServiceProtocol

    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }

    func startRecording() async throws -> URL {
        guard recorder == nil else { throw AudioRecordingError.alreadyRecording }
        guard await requestPermission() else { throw AudioRecordingError.permissionDenied }
        // Actor reentrancy: another start may have won while awaiting the permission prompt.
        guard recorder == nil else { throw AudioRecordingError.alreadyRecording }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            throw AudioRecordingError.sessionConfigurationFailed(error)
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("heirloom-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let newRecorder: AVAudioRecorder
        do {
            newRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        } catch {
            deactivateSession()
            throw AudioRecordingError.sessionConfigurationFailed(error)
        }
        newRecorder.isMeteringEnabled = true

        guard newRecorder.prepareToRecord(), newRecorder.record() else {
            deactivateSession()
            throw AudioRecordingError.recorderFailed
        }

        recorder = newRecorder
        interruptedDuration = nil
        observeInterruptionsIfNeeded()
        startMetering()
        return fileURL
    }

    func stopRecording() async throws -> (fileURL: URL, duration: TimeInterval) {
        guard let recorder else { throw AudioRecordingError.notRecording }

        let duration = interruptedDuration ?? recorder.currentTime
        let fileURL = recorder.url
        if recorder.isRecording {
            recorder.stop()
        }
        tearDown()
        return (fileURL, duration)
    }

    func cancelRecording() async {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        tearDown()
    }

    func meteringStream() async -> AsyncStream<Float> {
        meteringContinuation?.finish()
        let (stream, continuation) = AsyncStream.makeStream(of: Float.self, bufferingPolicy: .bufferingNewest(1))
        if recorder == nil || interruptedDuration != nil {
            continuation.finish()
        } else {
            meteringContinuation = continuation
        }
        return stream
    }

    // MARK: - Private

    private func startMetering() {
        meteringTask?.cancel()
        meteringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.emitMeterLevel()
                try? await Task.sleep(for: Self.meteringInterval)
            }
        }
    }

    private func emitMeterLevel() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0)
        meteringContinuation?.yield(Self.normalizedLevel(fromDecibels: decibels))
    }

    private func tearDown() {
        stopMetering()
        recorder = nil
        interruptedDuration = nil
        deactivateSession()
    }

    private func stopMetering() {
        meteringTask?.cancel()
        meteringTask = nil
        meteringContinuation?.finish()
        meteringContinuation = nil
    }

    private func observeInterruptionsIfNeeded() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
            Task { await self.handleInterruptionBegan() }
        }
    }

    /// A phone call or Siri took the microphone. Finalize what was captured and end the metering stream,
    /// which tells the view model to finish the recording.
    private func handleInterruptionBegan() {
        guard let recorder, recorder.isRecording, interruptedDuration == nil else { return }
        interruptedDuration = recorder.currentTime
        recorder.stop()
        stopMetering()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    static func normalizedLevel(fromDecibels decibels: Float) -> Float {
        guard decibels.isFinite else { return 0 }
        let clamped = min(max(decibels, silenceFloorDecibels), 0)
        return (clamped - silenceFloorDecibels) / -silenceFloorDecibels
    }
}
