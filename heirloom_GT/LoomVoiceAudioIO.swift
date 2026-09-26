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
        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true)

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
        engine.attach(player)
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
        playbackFormat = player.outputFormat(forBus: 0)
        if let playbackFormat {
            playbackConverter = AVAudioConverter(from: targetFormat, to: playbackFormat)
        }

        input.removeTap(onBus: 0)
        let bufferSize = AVAudioFrameCount(max(hwFormat.sampleRate * 0.1, 1024))
        input.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, _ in
            self?.capture(buffer, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
        player.play()
        started = true
    }

    func stop() {
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

        lock.lock()
        let now = player.lastRenderTime ?? AVAudioTime(hostTime: mach_absolute_time())
        let lead = AVAudioTime(sampleTime: now.sampleTime + AVAudioFramePosition(playbackFormat.sampleRate * 0.15), atRate: playbackFormat.sampleRate)
        let when = nextPlayTime ?? lead
        if when.sampleTime < now.sampleTime {
            nextPlayTime = AVAudioTime(
                sampleTime: now.sampleTime + AVAudioFramePosition(playbackFormat.sampleRate * 0.05),
                atRate: playbackFormat.sampleRate
            )
        }
        let start = nextPlayTime ?? lead
        nextPlayTime = AVAudioTime(
            sampleTime: start.sampleTime + AVAudioFramePosition(dest.frameLength),
            atRate: playbackFormat.sampleRate
        )
        lock.unlock()

        player.scheduleBuffer(dest, at: start, options: [])
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
            "target_rate": Int(Self.targetRate)
        ]
    }

    private func capture(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let captureConverter, buffer.frameLength > 0 else { return }
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
        guard dest.frameLength > 0, let channels = dest.int16ChannelData else { return }

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
