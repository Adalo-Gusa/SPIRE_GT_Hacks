import SwiftUI

private struct ChatLine: Identifiable {
    let id: UUID
    var sender: String
    var text: String
    var streaming: Bool

    init(sender: String, text: String, streaming: Bool = false) {
        self.id = UUID()
        self.sender = sender
        self.text = text
        self.streaming = streaming
    }
}

struct LoomDebugView: View {
    @StateObject private var voice = LoomVoiceSession()
    @State private var messages: [ChatLine] = []
    @State private var draft = ""
    @State private var isBusy = false
    @State private var threadId = UUID().uuidString
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                Divider()
                composer
            }
            .navigationTitle("Loomie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("Run Memory Recall Test") {
                        Task { await runMemoryRecallTest() }
                    }
                    .disabled(isBusy || voice.isLive)
                }
            }
            .onAppear(perform: bindVoice)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.sender)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(senderColor(message.sender))
                            Text(message.text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(senderBackground(message.sender), in: RoundedRectangle(cornerRadius: 10))
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(voice.composerPlaceholder, text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(isBusy)

            composerButton
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityHint(voice.composerPlaceholder)
    }

    @ViewBuilder
    private var composerButton: some View {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if voice.isLive && trimmed.isEmpty {
            Button(action: voice.stop) {
                VoiceWaveformIcon(phase: voice.phase, reduceMotion: reduceMotion)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Stop voice")
            .accessibilityHint("Hangs up. Loomie answers on her own when you pause.")
            .accessibilityValue(voice.sessionId)
        } else if !trimmed.isEmpty {
            Button {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                draft = ""
                guard !text.isEmpty else { return }
                if voice.isLive {
                    voice.sendTypedText(text)
                } else {
                    messages.append(ChatLine(sender: "You", text: text))
                    startVoice(openingText: text)
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
            .accessibilityLabel("Send")
        } else {
            Button {
                startVoice()
            } label: {
                Image(systemName: "waveform")
                    .font(.body.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)
            .accessibilityLabel("Start voice")
        }
    }

    private func startVoice(openingText: String? = nil) {
        if openingText == nil {
            append(.init(sender: "Test", text: "Loomie will say hello, then listen. Just talk — she answers when you pause. Tap the waveform again to hang up. Headphones help."))
        }
        bindVoice()
        voice.start(threadId: threadId, openingText: openingText)
    }

    private func bindVoice() {
        voice.onBeginUserTurn = {
            finishStreaming()
            messages.append(ChatLine(sender: "You", text: "…", streaming: true))
        }
        voice.onUpdateUserTurn = { text in
            if let index = messages.lastIndex(where: { $0.sender == "You" && $0.streaming }) {
                messages[index].text = text
            } else {
                messages.append(ChatLine(sender: "You", text: text, streaming: true))
            }
        }
        voice.onUpdateAssistantTurn = { text in
            if let index = messages.lastIndex(where: { $0.sender == "Loomie" && $0.streaming }) {
                messages[index].text = text
            } else {
                messages.append(ChatLine(sender: "Loomie", text: text, streaming: true))
            }
        }
        voice.onTurnFinished = { finishStreaming() }
        voice.onTranscript = { sender, text in
            finishStreaming()
            messages.append(ChatLine(sender: sender, text: text))
        }
    }

    private func finishStreaming() {
        for index in messages.indices {
            messages[index].streaming = false
        }
    }

    @MainActor
    private func runMemoryRecallTest() async {
        isBusy = true
        threadId = UUID().uuidString
        messages.append(ChatLine(
            sender: "Test",
            text: "Starting memory recall test on a fresh thread. Prompt 2 will not repeat the story."
        ))

        let story = "In 1970, I worked at a print shop in Chicago with my brother Arthur."
        let probe = "Where did I work and who was with me?"

        messages.append(ChatLine(sender: "You", text: story))
        do {
            let firstReply = try await LoomService.shared.sendMessage(text: story, threadId: threadId)
            messages.append(ChatLine(sender: "Loomie", text: firstReply))
        } catch {
            messages.append(ChatLine(sender: "Error", text: error.localizedDescription))
            messages.append(ChatLine(sender: "Test", text: "❌ Memory test aborted: first turn failed."))
            isBusy = false
            return
        }

        try? await Task.sleep(for: .seconds(1.2))

        messages.append(ChatLine(sender: "You", text: probe))
        let secondReply: String
        do {
            secondReply = try await LoomService.shared.sendMessage(text: probe, threadId: threadId)
            messages.append(ChatLine(sender: "Loomie", text: secondReply))
        } catch {
            messages.append(ChatLine(sender: "Error", text: error.localizedDescription))
            messages.append(ChatLine(sender: "Test", text: "❌ Memory test aborted: recall turn failed."))
            isBusy = false
            return
        }

        let haystack = secondReply.lowercased()
        let recalledPlace = haystack.contains("print") || haystack.contains("chicago")
        let recalledPerson = haystack.contains("arthur")
        let leakedStory = probe.lowercased().contains("print") || probe.lowercased().contains("arthur")

        if recalledPlace && recalledPerson && !leakedStory {
            messages.append(ChatLine(
                sender: "Test",
                text: "✅ Recalled print shop / Chicago and Arthur from Backboard memory without repeating them in prompt 2."
            ))
        } else {
            messages.append(ChatLine(
                sender: "Test",
                text: "❌ Recall check failed. place=\(recalledPlace) person=\(recalledPerson) leakedInPrompt2=\(leakedStory)"
            ))
        }
        isBusy = false
    }

    private func append(_ line: ChatLine) {
        messages.append(line)
    }

    private func senderColor(_ sender: String) -> Color {
        switch sender {
        case "Loomie": return .indigo
        case "You": return .primary
        case "Error": return .red
        default: return .secondary
        }
    }

    private func senderBackground(_ sender: String) -> Color {
        switch sender {
        case "Loomie": return Color.indigo.opacity(0.10)
        case "Error": return Color.red.opacity(0.10)
        case "Test": return Color.orange.opacity(0.12)
        default: return Color.gray.opacity(0.10)
        }
    }
}

private struct VoiceWaveformIcon: View {
    var phase: LoomVoiceSession.Phase
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: interval, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(.white)
                        .frame(width: 3, height: barHeight(index, t: t))
                }
            }
            .frame(width: 28, height: 28)
            .opacity(dimmed ? 0.78 : 1)
        }
    }

    private var interval: Double {
        switch phase {
        case .speaking: return 0.08
        case .listening: return 0.16
        default: return 0.28
        }
    }

    private var dimmed: Bool {
        phase == .connecting || phase == .thinking
    }

    private func barHeight(_ index: Int, t: TimeInterval) -> CGFloat {
        if reduceMotion { return 10 }
        let speed: Double
        switch phase {
        case .speaking: speed = 10
        case .listening: speed = 5
        default: speed = 2.4
        }
        let wave = sin(t * speed + Double(index) * 0.9)
        let scale = 0.4 + 0.6 * (0.5 + 0.5 * wave)
        return 16 * scale
    }
}

#Preview {
    LoomDebugView()
}
