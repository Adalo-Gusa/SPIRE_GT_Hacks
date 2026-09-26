import AVFoundation
import Foundation

@MainActor
final class LoomVoiceSession: ObservableObject {
    enum Phase: String {
        case idle
        case connecting
        case listening
        case thinking
        case speaking
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var sessionId = ""
    @Published var errorMessage: String?

    var onTranscript: ((String, String) -> Void)?
    var onBeginUserTurn: (() -> Void)?
    var onUpdateUserTurn: ((String) -> Void)?
    var onUpdateAssistantTurn: ((String) -> Void)?
    var onTurnFinished: (() -> Void)?

    var isLive: Bool { phase != .idle }

    var composerPlaceholder: String {
        switch phase {
        case .idle:
            return "Say hi, or tell Loomie a story…"
        case .connecting:
            return "Connecting…"
        case .listening:
            return "Listening · session \(sessionId)"
        case .thinking:
            return "Thinking · session \(sessionId)"
        case .speaking:
            return "Speaking · session \(sessionId)"
        }
    }

    private var webSocket: URLSessionWebSocketTask?
    private var socketSession: URLSession?
    private var audioIO: LoomVoiceAudioIO?
    private var logger: VoiceDebugLogger?
    private var pendingAudio: [Data] = []
    private var socketOpen = false
    private var threadId = ""
    private var currentUserItemId: String?
    private var currentUserText = ""
    private var currentAssistantText = ""
    private var persistedItemIDs = Set<String>()
    private var pendingInstructions = ""
    private var didConfigureSession = false
    private var didGreet = false
    private var connectStarted = Date()
    private var audioInChunks = 0
    private var audioInBytes = 0
    private var audioInRmsMax: Float = 0
    private var audioInRmsSum: Float = 0
    private var lastAudioInLog = Date()
    private var outDeltas = 0
    private var outBytes = 0
    private var firstDeltaLogged = false
    private var responseCreatedAt: Date?
    private var speechStoppedAt: Date?
    private var sessionFacts: [String] = []
    private var seedMemories: [String] = []

    func start(threadId: String) {
        guard phase == .idle else { return }
        self.threadId = threadId
        sessionId = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        logger = VoiceDebugLogger(sessionId: sessionId)
        errorMessage = nil
        pendingAudio.removeAll()
        socketOpen = false
        didConfigureSession = false
        didGreet = false
        connectStarted = Date()
        currentUserItemId = nil
        currentUserText = ""
        currentAssistantText = ""
        sessionFacts = []
        seedMemories = []
        persistedItemIDs.removeAll()
        setPhase(.connecting)
        logger?.log("start", ["url": AppConfiguration.grokRealtimeURL.absoluteString, "target_rate": Int(AppConfiguration.grokVoiceSampleRate)])

        Task { await connect() }
    }

    func stop() {
        guard phase != .idle else { return }
        logger?.log("stop", ["by": "client", "phase": phase.rawValue])
        tearDown()
    }

    func sendTypedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLive, !trimmed.isEmpty else { return }
        onTranscript?("You", trimmed)
        sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": trimmed]]
            ]
        ])
        sendJSON(["type": "response.create"])
        currentUserText = trimmed
        currentUserItemId = UUID().uuidString
    }

    // MARK: - Connect

    private func connect() async {
        let tokenStarted = Date()
        let token: String
        do {
            token = try await mintEphemeralToken()
            logger?.log("token.ok", ["ms": Int(Date().timeIntervalSince(tokenStarted) * 1000)])
        } catch {
            fail("token", error.localizedDescription, ms: Int(Date().timeIntervalSince(tokenStarted) * 1000))
            return
        }

        let micStarted = Date()
        let io = LoomVoiceAudioIO()
        io.onCapture = { [weak self] data, rms in
            Task { @MainActor in self?.enqueueMic(data, rms: rms) }
        }
        io.onError = { [weak self] message in
            Task { @MainActor in self?.fail("mic", message) }
        }
        do {
            try io.start()
            audioIO = io
            logger?.log("mic.ok", ["ms": Int(Date().timeIntervalSince(micStarted) * 1000), "label": "default"])
            var env = io.snapshot()
            env["ua"] = "heirloom_GT iOS"
            logger?.log("env", env)
        } catch {
            fail("mic", error.localizedDescription, ms: Int(Date().timeIntervalSince(micStarted) * 1000))
            return
        }

        let memories = await LoomService.shared.recallMemories(query: "", threadId: threadId)
        seedMemories = memories
        pendingInstructions = Self.voiceInstructions(memories: memories, sessionFacts: [])

        logger?.log("ws.connecting", [:])
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration)
        socketSession = session

        var request = URLRequest(url: AppConfiguration.grokRealtimeURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        webSocket = task
        task.resume()
        listen()
    }

    private func mintEphemeralToken() async throws -> String {
        guard !AppConfiguration.grokAPIKey.isEmpty else { throw LoomError.missingAPIKey("XAI_API_KEY") }
        var request = URLRequest(url: AppConfiguration.grokClientSecretsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(AppConfiguration.grokAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expires_after": ["seconds": 300]])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoomError.httpStatus(status, body)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let value = json?["value"] as? String, !value.isEmpty else {
            throw LoomError.emptyReply
        }
        return value
    }

    private func sendSessionUpdate(instructions: String) {
        sendJSON([
            "type": "session.update",
            "session": [
                "voice": AppConfiguration.grokVoiceName,
                "instructions": instructions,
                "turn_detection": ["type": "server_vad"],
                "reasoning": ["effort": "none"],
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": Int(AppConfiguration.grokVoiceSampleRate)],
                        "transcription": ["model": "grok-transcribe"]
                    ],
                    "output": [
                        "format": ["type": "audio/pcm", "rate": Int(AppConfiguration.grokVoiceSampleRate)]
                    ]
                ]
            ]
        ])
    }

    private static func voiceInstructions(memories: [String], sessionFacts: [String]) -> String {
        var text = AppConfiguration.loomieVoiceInstructions
        let longTerm = memories.prefix(12)
        if longTerm.isEmpty {
            text += "\nNo prior family memories are on file yet."
        } else {
            text += "\nKnown family memories from earlier sessions:\n"
            text += longTerm.map { "- \($0)" }.joined(separator: "\n")
        }
        if !sessionFacts.isEmpty {
            text += "\nFacts the speaker already shared in this live conversation. Use these if they ask you to recall:\n"
            text += sessionFacts.suffix(12).map { "- \($0)" }.joined(separator: "\n")
        }
        return text
    }

    // MARK: - Socket I/O

    private func listen() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    if self.webSocket != nil {
                        self.listen()
                    }
                case .failure(let error):
                    self.fail("ws", error.localizedDescription)
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleJSON(text)
        case .data(let data):
            audioIO?.playPCM16(data)
        @unknown default:
            break
        }
    }

    private func handleJSON(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = object["type"] as? String ?? ""

        if type == "response.output_audio.delta" || type == "response.audio.delta" {
            let b64 = (object["delta"] as? String) ?? (object["audio"] as? String) ?? ""
            if let pcm = Data(base64Encoded: b64) {
                if !firstDeltaLogged {
                    firstDeltaLogged = true
                    let sinceCreated = responseCreatedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                    let sinceSpeech = speechStoppedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                    logger?.log("audio.out.first", [
                        "response_id": object["response_id"] as? String ?? "",
                        "bytes": pcm.count,
                        "since_response_created_ms": sinceCreated,
                        "since_speech_stopped_ms": sinceSpeech,
                        "play_state": audioIO?.snapshot()["play_state"] ?? "unknown"
                    ])
                }
                outDeltas += 1
                outBytes += pcm.count
                audioIO?.playPCM16(pcm)
            }
            setPhase(.speaking)
            return
        }

        logger?.server(object, extra: ["phase": phase.rawValue])
        markSocketOpenIfNeeded()

        switch type {
        case "session.created", "session.updated":
            configureSessionIfNeeded()
            setPhase(.listening)
            greetIfNeeded(type)

        case "input_audio_buffer.speech_started":
            audioIO?.stopPlayback()
            logger?.log("play.stop", ["reason": "barge-in", "dropped_ms": 0])
            currentAssistantText = ""
            setPhase(.listening)

        case "input_audio_buffer.speech_stopped":
            speechStoppedAt = Date()
            setPhase(.thinking)

        case "input_audio_buffer.committed":
            currentUserItemId = object["item_id"] as? String
            currentUserText = ""
            onBeginUserTurn?()

        case "conversation.item.input_audio_transcription.updated",
             "conversation.item.input_audio_transcription.completed":
            if let transcript = (object["transcript"] as? String) ?? (object["text"] as? String) {
                currentUserText = transcript
                onUpdateUserTurn?(transcript)
            }

        case "response.created":
            responseCreatedAt = Date()
            firstDeltaLogged = false
            outDeltas = 0
            outBytes = 0
            currentAssistantText = ""
            setPhase(.thinking)

        case "response.output_audio_transcript.delta":
            if let delta = object["delta"] as? String {
                currentAssistantText += delta
                onUpdateAssistantTurn?(currentAssistantText)
            }
            setPhase(.speaking)

        case "response.output_audio_transcript.done":
            if let transcript = object["transcript"] as? String, !transcript.isEmpty {
                currentAssistantText = transcript
                onUpdateAssistantTurn?(transcript)
            }

        case "response.done":
            logger?.log("audio.out", [
                "response_id": object["response_id"] as? String ?? "",
                "status": (object["response"] as? [String: Any])?["status"] ?? "completed",
                "deltas": outDeltas,
                "bytes": outBytes
            ])
            persistUserTurn()
            onTurnFinished?()
            setPhase(.listening)

        case "error":
            let detail = (object["error"] as? [String: Any])?["message"] as? String
                ?? object["message"] as? String
                ?? "Voice session error"
            fail("server", detail)

        default:
            break
        }
    }

    private func markSocketOpenIfNeeded() {
        guard !socketOpen else { return }
        socketOpen = true
        logger?.log("ws.open", ["ms": Int(Date().timeIntervalSince(connectStarted) * 1000)])
        configureSessionIfNeeded()
        flushPendingAudio()
        if phase == .connecting {
            setPhase(.listening)
        }
    }

    private func configureSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        sendSessionUpdate(instructions: pendingInstructions)
    }

    private func greetIfNeeded(_ type: String) {
        guard type == "session.updated", !didGreet else { return }
        didGreet = true
        sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "force_message",
                "role": "assistant",
                "interruptible": true,
                "content": [["type": "output_text", "text": "Hi, I'm Loomie. It's so nice to hear from you."]]
            ]
        ])
    }

    private func enqueueMic(_ data: Data, rms: Float) {
        audioInChunks += 1
        audioInBytes += data.count
        audioInRmsMax = max(audioInRmsMax, rms)
        audioInRmsSum += rms
        if Date().timeIntervalSince(lastAudioInLog) >= 2 {
            logger?.log("audio.in", [
                "chunks": audioInChunks,
                "bytes": audioInBytes,
                "rms_max": audioInRmsMax,
                "rms_avg": audioInChunks == 0 ? 0 : audioInRmsSum / Float(audioInChunks),
                "pending": pendingAudio.count,
                "phase": phase.rawValue
            ])
            audioInChunks = 0
            audioInBytes = 0
            audioInRmsMax = 0
            audioInRmsSum = 0
            lastAudioInLog = Date()
        }

        if !socketOpen {
            if pendingAudio.count < 50 {
                pendingAudio.append(data)
            }
            return
        }
        sendAudio(data)
    }

    private func flushPendingAudio() {
        guard !pendingAudio.isEmpty else { return }
        logger?.log("audio.flush", ["chunks": pendingAudio.count])
        pendingAudio.forEach(sendAudio)
        pendingAudio.removeAll()
    }

    private func sendAudio(_ data: Data) {
        sendJSON([
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ], logClient: false)
    }

    private func sendJSON(_ object: [String: Any], logClient: Bool = true) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        if logClient {
            logger?.client(object)
        }
        webSocket?.send(.string(text)) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.logger?.error(where: "ws.send", message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Transcript helpers

    private func persistUserTurn() {
        let item = currentUserItemId ?? currentUserText
        guard !item.isEmpty else { return }
        if persistedItemIDs.contains(item) { return }
        persistedItemIDs.insert(item)
        Task { await absorbFact(currentUserText) }
    }

    private func absorbFact(_ text: String) async {
        let utterance = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ConversationMemory.shouldStore(utterance) else { return }
        if sessionFacts.contains(where: { $0.caseInsensitiveCompare(utterance) == .orderedSame }) {
            return
        }
        sessionFacts.append(utterance)
        let stored = await LoomService.shared.rememberIfNeeded(utterance, threadId: threadId)
        logger?.log("memory.store", ["stored": stored, "facts": sessionFacts.count])
        let memories = await LoomService.shared.recallMemories(query: utterance, threadId: threadId)
        if !memories.isEmpty {
            seedMemories = memories
        }
        pendingInstructions = Self.voiceInstructions(memories: seedMemories, sessionFacts: sessionFacts)
        sendSessionUpdate(instructions: pendingInstructions)
    }

    // MARK: - Lifecycle

    private func setPhase(_ next: Phase) {
        guard phase != next else { return }
        phase = next
        logger?.log("phase", ["phase": next.rawValue])
    }

    private func fail(_ whereFrom: String, _ message: String, ms: Int? = nil) {
        var extra: [String: Any] = [:]
        if let ms { extra["ms"] = ms }
        logger?.error(where: whereFrom, message: message, extra: extra)
        errorMessage = "\(message) (voice session \(sessionId))"
        onTranscript?("Error", errorMessage ?? message)
        tearDown()
    }

    private func tearDown() {
        logger?.log("ws.close", ["code": 1000, "reason": "client stop", "wasClean": true, "by": "client"])
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        socketSession?.invalidateAndCancel()
        socketSession = nil
        audioIO?.stop()
        audioIO = nil
        socketOpen = false
        pendingAudio.removeAll()
        didGreet = false
        didConfigureSession = false
        logger?.close()
        logger = nil
        phase = .idle
    }
}
