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
    @StateObject private var archive = LoomVoiceViewModel()
    @State private var messages: [ChatLine] = []
    @State private var draft = ""
    @State private var isBusy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                storyPanel
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
            .onChange(of: messages.last?.text) { _, _ in
                if let last = messages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private var storyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let artifact = archive.savedArtifacts.first {
                artifactCard(artifact)
            }
            VStack(alignment: .leading, spacing: 8) {
                if isBusy {
                    ProgressView()
                }
                Button("Wrap Up & Save Story") {
                    Task { await wrapUpStory() }
                }
                .disabled(isBusy || voice.isLive || !hasStoryTurns)
                Button("New Conversation (Clear Thread)") {
                    startFreshThread(note: "New conversation. Saved stories stay in Backboard.")
                }
                .disabled(isBusy)
                Button("Run Cross-Session Story Test") {
                    Task { await runCrossSessionStoryTest() }
                }
                .disabled(isBusy || voice.isLive)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func artifactCard(_ artifact: StoryArtifact) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(artifact.title)
                .font(.subheadline.weight(.semibold))
            Text(artifact.narrativeSummary)
            labeled("Era", artifact.extractedEra ?? "—")
            labeled("Location", artifact.location ?? "—")
            labeled("People", artifact.peopleMentioned.joined(separator: ", "))
            labeled("Passions", artifact.passionsOrHobbies.joined(separator: ", "))
            labeled("Imagine", artifact.grokImaginePrompt)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        Text("\(title): \(value.isEmpty ? "—" : value)")
            .foregroundStyle(.secondary)
    }

    private var hasStoryTurns: Bool {
        messages.contains { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (line.sender == "You" || line.sender == "Loomie") && !text.isEmpty && text != "…"
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
        voice.start(threadId: archive.threadId, openingText: openingText)
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
        archive.beginNewThread()
        let threadId = archive.threadId
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

    @MainActor
    private func wrapUpStory() async {
        isBusy = true
        if voice.isLive { voice.stop() }
        let turns = messages.map { ConversationTurn(sender: $0.sender, text: $0.text) }
        do {
            let artifact = try await archive.finishAndSaveConversation(turns: turns)
            messages = [ChatLine(
                sender: "Test",
                text: "Saved “\(artifact.title)” to Backboard and this phone. This is a new conversation."
            )]
        } catch {
            print("[Loomie] wrap-up failed: \(error.localizedDescription)")
            messages.append(ChatLine(sender: "Error", text: error.localizedDescription))
        }
        isBusy = false
    }

    @MainActor
    private func startFreshThread(note: String) {
        if voice.isLive { voice.stop() }
        archive.beginNewThread()
        draft = ""
        messages = [ChatLine(sender: "Test", text: note)]
    }

    @MainActor
    private func runCrossSessionStoryTest() async {
        isBusy = true
        if voice.isLive { voice.stop() }
        archive.beginNewThread()
        messages = [ChatLine(
            sender: "Test",
            text: "Cross-session test. Conversation 1 will be wrapped up, then a new thread will ask about the car project."
        )]

        let story = "In 1968 I spent the summer fixing cars with Uncle Bob. We restored a Mustang in his garage."
        let firstThread = archive.threadId
        messages.append(ChatLine(sender: "You", text: story))
        do {
            let firstReply = try await LoomService.shared.sendMessage(text: story, threadId: firstThread)
            messages.append(ChatLine(sender: "Loomie", text: firstReply))
        } catch {
            messages.append(ChatLine(sender: "Error", text: error.localizedDescription))
            messages.append(ChatLine(sender: "Test", text: "Cross-session test aborted: first conversation failed."))
            isBusy = false
            return
        }

        let turns = messages.map { ConversationTurn(sender: $0.sender, text: $0.text) }
        do {
            let artifact = try await archive.finishAndSaveConversation(turns: turns)
            messages = [ChatLine(
                sender: "Test",
                text: "Wrapped up “\(artifact.title)”. Starting conversation 2 on a new thread."
            )]
        } catch {
            messages.append(ChatLine(sender: "Error", text: error.localizedDescription))
            messages.append(ChatLine(sender: "Test", text: "Cross-session test aborted: wrap-up failed."))
            isBusy = false
            return
        }

        try? await Task.sleep(for: .seconds(1.5))

        let probe = "Do you remember what car project I worked on in my youth?"
        let secondThread = archive.threadId
        guard secondThread != firstThread else {
            messages.append(ChatLine(sender: "Test", text: "Cross-session test aborted: thread id did not change."))
            isBusy = false
            return
        }
        messages.append(ChatLine(sender: "You", text: probe))
        let secondReply: String
        do {
            secondReply = try await LoomService.shared.sendMessage(text: probe, threadId: secondThread)
            messages.append(ChatLine(sender: "Loomie", text: secondReply))
        } catch {
            messages.append(ChatLine(sender: "Error", text: error.localizedDescription))
            messages.append(ChatLine(sender: "Test", text: "Cross-session test aborted: recall turn failed."))
            isBusy = false
            return
        }

        let haystack = secondReply.lowercased()
        let recalledYear = haystack.contains("1968")
        let recalledPerson = haystack.contains("bob")
        let recalledProject = haystack.contains("mustang") || haystack.contains("car") || haystack.contains("restor")
        let leakedProbe = probe.lowercased().contains("1968") || probe.lowercased().contains("bob")
        if recalledYear && recalledPerson && recalledProject && !leakedProbe {
            messages.append(ChatLine(
                sender: "Test",
                text: "Recalled the 1968 car restoration with Uncle Bob from Backboard on a new thread."
            ))
        } else {
            messages.append(ChatLine(
                sender: "Test",
                text: "Cross-session recall failed. year=\(recalledYear) person=\(recalledPerson) project=\(recalledProject)"
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
