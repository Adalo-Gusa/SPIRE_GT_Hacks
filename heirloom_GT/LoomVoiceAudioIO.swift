import AVFoundation
import Darwin
import Foundation

final class LoomVoiceAudioIO {
    static let targetRate: Double = AppConfiguration.grokVoiceSampleRate

    var onCapture: ((Data, Float) -> Void)?
    var onError: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var captureConverter: AVAudioConverter?
    private var playbackConverter: AVAudioConverter?
    private var playbackFormat: AVAudioFormat?
    private var nextPlayTime: AVAudioTime?
    private var oddByte: UInt8?
    private var started = false
    private let lock = NSLock()

    // Capture diagnostics, reported through `snapshot()` (guarded by `lock`).
    private var hwFormatDescription = ""
    private var tapBuffers = 0
    private var capturedChunks = 0
    private var convertFailures = 0
    private var lastCaptureError = ""
    private var configChanges = 0
    private var runningAfterStart = false
    private var configObserver: NSObjectProtocol?

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try session.setPreferredSampleRate(Self.targetRate)
        try session.setActive(true)

        // Voice processing reconfigures the I/O formats, so enable it before connecting nodes or reading formats.
        try? engine.inputNode.setVoiceProcessingEnabled(true)
        engine.attach(player)

        // Enabling voice processing (and route changes like plugging in headphones) makes iOS reconfigure the
        // audio hardware, which silently stops the engine right after it starts. Without a restart the mic tap
        // never fires, so no audio reaches Grok. Rebuild the graph and restart whenever that happens.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        try configureGraphAndStart()
        runningAfterStart = engine.isRunning
        started = true
    }

    /// Connects the player, builds converters for the current hardware formats, installs the mic tap and
    /// starts the engine. Safe to call again after a configuration change.
    private func configureGraphAndStart() throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        engine.disconnectNodeOutput(player)

        // Give the player an explicit mono format at the output rate and let the mixer upmix/route it.
        // scheduleBuffer requires buffers to match the player's output format exactly (including channel
        // count), so playback buffers are built from the player's format below, not the mixer's.
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard let playerFormat = AVAudioFormat(
            standardFormatWithSampleRate: outputRate > 0 ? outputRate : Self.targetRate,
            channels: 1
        ) else {
            throw LoomError.decoding("Could not build playback format.")
        }
        engine.connect(player, to: engine.mainMixerNode, format: playerFormat)

        let hwFormat = input.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw LoomError.decoding("Microphone hardware format is unavailable.")
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetRate,
            channels: 1,
            interleaved: true
        ) else {
            throw LoomError.decoding("Could not build 24 kHz PCM format.")
        }

        captureConverter = AVAudioConverter(from: hwFormat, to: targetFormat)
        hwFormatDescription = "\(hwFormat.sampleRate)Hz \(hwFormat.channelCount)ch \(hwFormat.commonFormat.rawValue) interleaved=\(hwFormat.isInterleaved)"
        if captureConverter == nil {
            lastCaptureError = "no converter for \(hwFormatDescription)"
        }
        playbackFormat = player.outputFormat(forBus: 0)
        playbackConverter = playbackFormat.flatMap { AVAudioConverter(from: targetFormat, to: $0) }

        // Scheduled playback times belong to the old engine timeline.
        lock.lock()
        nextPlayTime = nil
        lock.unlock()

        let bufferSize = AVAudioFrameCount(max(hwFormat.sampleRate * 0.1, 1024))
        input.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, _ in
            self?.capture(buffer, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
        player.play()
    }

    private func handleConfigurationChange() {
        lock.lock()
        configChanges += 1
        let changes = configChanges
        lock.unlock()
        guard started else { return }
        // A handful of changes is normal (voice processing, route changes); endless ones mean something is wrong.
        guard changes <= 10 else {
            onError?("The audio device keeps reconfiguring; stopping the voice session.")
            return
        }
        do {
            try configureGraphAndStart()
        } catch {
            onError?("Could not restart audio: \(error.localizedDescription)")
        }
    }

    func stop() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        started = false
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        started = false
        nextPlayTime = nil
        oddByte = nil
    }

    func playPCM16(_ data: Data) {
        guard started, !data.isEmpty else { return }

        var samples = data
        lock.lock()
        if let leftover = oddByte {
            samples = Data([leftover]) + samples
            oddByte = nil
        }
        if samples.count % 2 == 1 {
            oddByte = samples.removeLast()
        }
        lock.unlock()
        guard !samples.isEmpty else { return }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetRate,
            channels: 1,
            interleaved: true
        ) else { return }

        let frameCount = AVAudioFrameCount(samples.count / 2)
        guard let source = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
        source.frameLength = frameCount
        samples.withUnsafeBytes { raw in
            guard let src = raw.baseAddress, let dst = source.int16ChannelData?[0] else { return }
            memcpy(dst, src, samples.count)
        }

        guard let playbackFormat, let playbackConverter else { return }
        let ratio = playbackFormat.sampleRate / targetFormat.sampleRate
        let outFrames = AVAudioFrameCount(Double(frameCount) * ratio) + 32
        guard let dest = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: outFrames) else { return }

        var error: NSError?
        var supplied = false
        playbackConverter.convert(to: dest, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return source
        }
        if dest.frameLength == 0 { return }

        // Anchor to the player clock. AVAudioTime(sampleTime:atRate:) is only valid after playerTime(forNodeTime:).
        let nodeTime = player.lastRenderTime
        let playerTime = nodeTime.flatMap { player.playerTime(forNodeTime: $0) }
        lock.lock()
        let when: AVAudioTime?
        if let playerTime, playerTime.isSampleTimeValid {
            let rate = playerTime.sampleRate
            let now = playerTime.sampleTime
            let lead = AVAudioFramePosition(rate * 0.15)
            var startSample = now + lead
            if let queued = nextPlayTime, queued.isSampleTimeValid, queued.sampleTime > now {
                startSample = queued.sampleTime
            }
            when = AVAudioTime(sampleTime: startSample, atRate: rate)
            nextPlayTime = AVAudioTime(
                sampleTime: startSample + AVAudioFramePosition(dest.frameLength),
                atRate: rate
            )
        } else {
            when = nil
            nextPlayTime = nil
        }
        lock.unlock()

        player.scheduleBuffer(dest, at: when, options: [])
        if !player.isPlaying {
            player.play()
        }
    }

    func stopPlayback() {
        lock.lock()
        nextPlayTime = nil
        oddByte = nil
        lock.unlock()
        player.stop()
        player.play()
    }

    func snapshot() -> [String: Any] {
        let session = AVAudioSession.sharedInstance()
        return [
            "mic_rate": session.sampleRate,
            "mic_state": session.category.rawValue,
            "play_rate": engine.mainMixerNode.outputFormat(forBus: 0).sampleRate,
            "play_state": engine.isRunning ? "running" : "stopped",
            "capture_frames": Int(session.ioBufferDuration * session.sampleRate),
            "target_rate": Int(Self.targetRate),
            "record_permission": Self.recordPermissionDescription,
            "input_available": session.isInputAvailable,
            "hw_format": hwFormatDescription,
            "tap_buffers": tapBuffers,
            "captured_chunks": capturedChunks,
            "convert_failures": convertFailures,
            "last_capture_error": lastCaptureError,
            "config_changes": configChanges,
            "running_after_start": runningAfterStart
        ]
    }

    private static var recordPermissionDescription: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return "granted"
        case .denied: return "denied"
        case .undetermined: return "undetermined"
        @unknown default: return "unknown"
        }
    }

    private func noteCaptureFailure(_ message: String) {
        lock.lock()
        convertFailures += 1
        lastCaptureError = message
        lock.unlock()
    }

    private func capture(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        lock.lock()
        tapBuffers += 1
        lock.unlock()
        guard let captureConverter else {
            noteCaptureFailure("no converter for \(buffer.format)")
            return
        }
        guard buffer.frameLength > 0 else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let dest = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else { return }

        var error: NSError?
        var supplied = false
        captureConverter.convert(to: dest, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard dest.frameLength > 0, let channels = dest.int16ChannelData else {
            noteCaptureFailure(error?.localizedDescription ?? "converter produced no frames from \(buffer.format)")
            return
        }
        lock.lock()
        capturedChunks += 1
        lock.unlock()

        let byteCount = Int(dest.frameLength) * 2
        let data = Data(bytes: channels[0], count: byteCount)
        let rms = Self.rms(channels[0], count: Int(dest.frameLength))
        onCapture?(data, rms)
    }

    private static func rms(_ samples: UnsafePointer<Int16>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            let sample = Float(samples[i]) / 32768
            sum += sample * sample
        }
        return sqrt(sum / Float(count))
    }
}
