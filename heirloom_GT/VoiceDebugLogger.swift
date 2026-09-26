import Foundation

#if DEBUG
private let voiceLogEnabled = true
#else
private let voiceLogEnabled = false
#endif

/// Dev-only voice session logger. Never throws into the realtime path.
final class VoiceDebugLogger: @unchecked Sendable {
    let sessionId: String
    private let started = Date()
    private let lock = NSLock()
    private var buffer: [[String: Any]] = []
    private var flushWork: DispatchWorkItem?
    private let fileURL: URL?
    private let queue = DispatchQueue(label: "loom.voice.log")

    init(sessionId: String) {
        self.sessionId = sessionId
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("voice-logs", isDirectory: true)
        if let folder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            fileURL = folder.appendingPathComponent("\(sessionId).ndjson")
        } else {
            fileURL = nil
        }
    }

    func log(_ kind: String, _ data: [String: Any] = [:]) {
        guard voiceLogEnabled else { return }
        let redacted = (redact(data) as? [String: Any]) ?? data
        let entry = redacted.merging([
            "kind": kind,
            "t": Int(Date().timeIntervalSince(started) * 1000),
            "ts": Int(Date().timeIntervalSince1970 * 1000)
        ]) { _, new in new }

        lock.lock()
        buffer.append(entry)
        let overflow = buffer.count >= 200
        lock.unlock()

        print("[VoiceLog \(sessionId)] \(kind) \(shortJSON(entry))")
        if overflow {
            flush(final: false)
        } else {
            scheduleFlush()
        }
    }

    func server(_ event: [String: Any], extra: [String: Any] = [:]) {
        var payload = redactEvent(event)
        extra.forEach { payload[$0.key] = $0.value }
        log("server", payload)
    }

    func client(_ event: [String: Any]) {
        log("client", redactEvent(event))
    }

    func error(where whereFrom: String, message: String, extra: [String: Any] = [:]) {
        var payload: [String: Any] = ["where": whereFrom, "message": clip(message)]
        extra.forEach { payload[$0.key] = $0.value }
        log("error", payload)
    }

    func close() {
        flush(final: true)
    }

    private func scheduleFlush() {
        queue.async { [weak self] in
            self?.flushWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flush(final: false) }
            self?.flushWork = work
            self?.queue.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }

    private func flush(final: Bool) {
        lock.lock()
        let entries = buffer
        buffer.removeAll()
        lock.unlock()
        guard !entries.isEmpty else { return }

        queue.async { [weak self] in
            guard let self else { return }
            var lines = ""
            for entry in entries.prefix(500) {
                if JSONSerialization.isValidJSONObject(entry),
                   let data = try? JSONSerialization.data(withJSONObject: entry),
                   let line = String(data: data, encoding: .utf8),
                   line.count < 16_000 {
                    lines += line + "\n"
                }
            }
            guard !lines.isEmpty, let fileURL else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                if let data = lines.data(using: .utf8) {
                    handle.write(data)
                }
            } else {
                try? lines.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            if final {
                print("[VoiceLog \(self.sessionId)] wrote \(fileURL.path)")
            }
        }
    }

    private func redactEvent(_ event: [String: Any]) -> [String: Any] {
        let type = event["type"] as? String ?? ""
        if type == "response.output_audio.delta" || type == "response.audio.delta" || type == "input_audio_buffer.append" {
            var copy = event
            if let delta = copy["delta"] as? String {
                copy["delta"] = NSNull()
                copy["bytes"] = Data(base64Encoded: delta)?.count ?? delta.utf8.count
            }
            if let audio = copy["audio"] as? String {
                copy["audio"] = NSNull()
                copy["bytes"] = Data(base64Encoded: audio)?.count ?? audio.utf8.count
            }
            return redact(copy)
        }
        return redact(event)
    }

    private func redact(_ value: Any, depth: Int = 0) -> Any {
        if depth > 4 { return "[depth]" }
        if let string = value as? String {
            return clip(string)
        }
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, nested) in dict {
                out[key] = redact(nested, depth: depth + 1)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.prefix(50).map { redact($0, depth: depth + 1) }
        }
        return value
    }

    private func clip(_ string: String) -> String {
        guard string.count > 400 else { return string }
        return String(string.prefix(400)) + "…[\(string.count) chars]"
    }

    private func shortJSON(_ object: [String: Any]) -> String {
        var slim = object
        slim["delta"] = nil
        slim["audio"] = nil
        guard JSONSerialization.isValidJSONObject(slim),
              let data = try? JSONSerialization.data(withJSONObject: slim),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return clip(text)
    }
}
