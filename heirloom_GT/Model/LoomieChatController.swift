import Foundation

/// One bubble in the Loomie chat.
struct ChatLine: Identifiable, Equatable {
    enum Sender: Equatable {
        case you
        case loomie
        /// Status notes from the app (saved confirmations, errors).
        case app
    }

    let id = UUID()
    var sender: Sender
    var text: String
    /// Still being transcribed or spoken; its text keeps updating.
    var streaming = false
}

/// Drives the Loomie chat overlay: owns the live voice session, turns its callbacks into chat bubbles, and
/// saves the conversation as a story through the family archive.
@MainActor
final class LoomieChatController: ObservableObject {
    let voice = LoomVoiceSession()

    @Published private(set) var messages: [ChatLine] = []
    @Published private(set) var isSavingStory = false

    init() {
        bindVoice()
    }

    /// Whether the conversation has anything worth turning into a story.
    var hasStoryTurns: Bool {
        messages.contains { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.sender != .app && !text.isEmpty && text != "…"
        }
    }

    /// Starts listening (Loomie greets first), unless a session is already running.
    func start(threadId: String) {
        guard !voice.isLive else { return }
        voice.start(threadId: threadId)
    }

    func end() {
        if voice.isLive { voice.stop() }
    }

    /// Sends typed text; starts a session with it as the opening line if none is running.
    func send(_ text: String, threadId: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if voice.isLive {
            // The session echoes typed text back through `onTranscript`, which adds the bubble.
            voice.sendTypedText(trimmed)
        } else {
            messages.append(ChatLine(sender: .you, text: trimmed))
            voice.start(threadId: threadId, openingText: trimmed)
        }
    }

    /// Clears the chat and starts a fresh thread (saved stories are kept).
    func newConversation(archive: FamilyArchive) {
        end()
        archive.voiceModel.beginNewThread()
        messages = []
    }

    /// Ends the session and saves the conversation as a story: Backboard memory, MongoDB Atlas, and the phone.
    func generateStory(archive: FamilyArchive) async {
        guard !isSavingStory else { return }
        isSavingStory = true
        defer { isSavingStory = false }
        end()

        let turns = messages.compactMap { line -> ConversationTurn? in
            switch line.sender {
            case .you: return ConversationTurn(sender: "You", text: line.text)
            case .loomie: return ConversationTurn(sender: "Loomie", text: line.text)
            case .app: return nil
            }
        }
        do {
            let artifact = try await archive.voiceModel.finishAndSaveConversation(turns: turns)
            messages = [ChatLine(sender: .app, text: "Saved “\(artifact.title)” to the Family Notebook.")]
            await archive.refresh()
        } catch {
            messages.append(ChatLine(sender: .app, text: "Couldn't save the story: \(error.localizedDescription)"))
        }
    }

    // MARK: - Voice callbacks → bubbles

    private func bindVoice() {
        voice.onBeginUserTurn = { [weak self] in
            self?.finishStreaming()
            self?.messages.append(ChatLine(sender: .you, text: "…", streaming: true))
        }
        voice.onUpdateUserTurn = { [weak self] text in
            self?.updateStreaming(.you, text: text)
        }
        voice.onUpdateAssistantTurn = { [weak self] text in
            self?.updateStreaming(.loomie, text: text)
        }
        voice.onTurnFinished = { [weak self] in
            self?.finishStreaming()
        }
        voice.onTranscript = { [weak self] sender, text in
            self?.finishStreaming()
            let mapped: ChatLine.Sender = switch sender {
            case "You": .you
            case "Loomie": .loomie
            default: .app
            }
            self?.messages.append(ChatLine(sender: mapped, text: text))
        }
    }

    private func updateStreaming(_ sender: ChatLine.Sender, text: String) {
        if let index = messages.lastIndex(where: { $0.sender == sender && $0.streaming }) {
            messages[index].text = text
        } else {
            messages.append(ChatLine(sender: sender, text: text, streaming: true))
        }
    }

    private func finishStreaming() {
        for index in messages.indices where messages[index].streaming {
            messages[index].streaming = false
        }
    }
}
