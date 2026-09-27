import SwiftUI

/// Loomie's voice chat, shown over the Home board: a blurred cover with chat bubbles, a status pill,
/// and basic controls. Opened from the yarn button.
struct LoomieChatOverlay: View {
    @ObservedObject var controller: LoomieChatController
    @EnvironmentObject private var archive: FamilyArchive
    var initialPrompt: String? = nil
    var onClose: () -> Void

    @Environment(\.tabBarTop) private var tabBarTop
    @State private var draft = ""

    var body: some View {
        GeometryReader { proxy in
            // Keep everything above the yarn button, which rises into this space.
            let bottomClearance = tabBarTop.map { max(0, proxy.frame(in: .global).maxY - $0) + 12 } ?? 16

            VStack(spacing: 12) {
                header
                bubbles
                controls
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, bottomClearance)
        }
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                HeirloomColor.plum.opacity(0.12)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            controller.start(threadId: archive.voiceModel.threadId, initialPrompt: initialPrompt)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Loomie")
                .font(.heirloomDisplay(28, relativeTo: .title))
                .foregroundStyle(HeirloomColor.plum)
            Spacer()
            LoomieStatusPill(voice: controller.voice)
        }
    }

    // MARK: - Bubbles

    private var bubbles: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if controller.messages.isEmpty {
                        Text("Loomie will say hello, then listen. Tell her a family story — she answers when you pause.")
                            .font(.callout)
                            .foregroundStyle(HeirloomColor.tabLabel)
                            .multilineTextAlignment(.center)
                            .padding(.top, 40)
                    }
                    ForEach(controller.messages) { line in
                        ChatBubble(line: line)
                            .id(line.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: controller.messages.last?.text) { _, _ in
                if let last = controller.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Type to Loomie…", text: $draft)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassBackground(in: RoundedRectangle(cornerRadius: 20, style: .continuous), tint: .white.opacity(0.2))
                    .submitLabel(.send)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(HeirloomColor.rose)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }

            HStack(spacing: 8) {
                Button {
                    Task { await controller.generateStory(archive: archive) }
                } label: {
                    if controller.isSavingStory {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Generate story", systemImage: "book.closed").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(HeirloomColor.plum)
                .disabled(!controller.hasStoryTurns || controller.isSavingStory)

                Button("New chat") {
                    controller.newConversation(archive: archive)
                    controller.start(threadId: archive.voiceModel.threadId)
                }
                .buttonStyle(.bordered)
                .tint(HeirloomColor.plum)
                .disabled(controller.isSavingStory)

                Button("End", role: .destructive) {
                    controller.end()
                    onClose()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        controller.send(text, threadId: archive.voiceModel.threadId)
    }
}

/// A chat bubble: Loomie on the left, you on the right, app notes centered.
private struct ChatBubble: View {
    let line: ChatLine

    var body: some View {
        switch line.sender {
        case .loomie:
            bubble(fill: HeirloomColor.plum.opacity(0.85), text: HeirloomColor.board)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 48)
        case .you:
            bubble(fill: HeirloomColor.rose.opacity(0.9), text: .white)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 48)
        case .app:
            Text(line.text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(HeirloomColor.plum)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(HeirloomColor.polaroidFrame.opacity(0.9), in: Capsule())
                .frame(maxWidth: .infinity)
        }
    }

    private func bubble(fill: Color, text: Color) -> some View {
        Text(line.text)
            .font(.body)
            .foregroundStyle(text)
            .opacity(line.streaming ? 0.85 : 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Shows what Loomie is doing right now.
private struct LoomieStatusPill: View {
    @ObservedObject var voice: LoomVoiceSession

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(voice.isLive ? HeirloomColor.rose : HeirloomColor.tabLabel)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HeirloomColor.plum)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassBackground(in: Capsule(), tint: .white.opacity(0.2))
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch voice.phase {
        case .idle: "Not listening"
        case .connecting: "Connecting…"
        case .listening: "Listening"
        case .thinking: "Thinking…"
        case .speaking: "Speaking"
        }
    }
}
