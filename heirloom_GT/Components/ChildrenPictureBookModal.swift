import SwiftUI
import AVFoundation

/// Full-screen interactive Children's Picture Book Reader presenting a family memory
/// illustrated by xAI Grok Imagine, complete with read-aloud storytelling.
struct ChildrenPictureBookModal: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var archive: FamilyArchive

    let story: StoryDocument
    @State private var currentStory: StoryDocument
    @State private var isGenerating: Bool = false
    @State private var selectedStyle: String = "childrens_storybook"
    @State private var isSpeaking: Bool = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var errorMessage: String?

    init(story: StoryDocument) {
        self.story = story
        _currentStory = State(initialValue: story)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CorkboardBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        // MARK: - Storybook Cover / Illustration Spread
                        VStack(spacing: 12) {
                            illustrationSection
                            
                            // Storybook Title Header
                            Text(currentStory.title)
                                .font(.heirloomDisplay(26, relativeTo: .title2))
                                .foregroundStyle(HeirloomColor.plum)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)

                            if let subtitle {
                                Text(subtitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(HeirloomColor.tabLabel)
                            }
                        }
                        .padding(16)
                        .background(HeirloomColor.polaroidPhoto)
                        .padding(10)
                        .background(HeirloomColor.polaroidFrame)
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 5, y: 6)
                        .overlay(alignment: .top) {
                            Pushpin(showsHole: false)
                                .scaleEffect(0.5, anchor: .bottom)
                                .frame(height: Pushpin.size.height * 0.5)
                                .offset(y: -32)
                                .accessibilityHidden(true)
                        }

                        // MARK: - Children's Story Adaptation Text
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Picture Book Story", systemImage: "book.pages.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(HeirloomColor.rose)
                                    .textCase(.uppercase)

                                Spacer()

                                // Read-Aloud Voice Button
                                Button {
                                    toggleSpeech()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: isSpeaking ? "stop.circle.fill" : "speaker.wave.2.bubble.fill")
                                        Text(isSpeaking ? "Stop Voice" : "Read to Me")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isSpeaking ? HeirloomColor.rose.opacity(0.2) : HeirloomColor.polaroidFrame)
                                    .foregroundStyle(HeirloomColor.plum)
                                    .clipShape(Capsule())
                                }
                            }

                            Text(displayStoryText)
                                .font(.system(size: 19, weight: .regular, design: .serif))
                                .lineSpacing(6)
                                .foregroundStyle(HeirloomColor.plum)
                                .fixedSize(horizontal: false, vertical: true)

                            // MARK: - Family Wisdom & Knowledge Passing Down
                            if let moral = currentStory.childrenMoral ?? defaultMoral {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "sparkles")
                                        .font(.title3)
                                        .foregroundStyle(HeirloomColor.rose)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Wisdom for the Kids")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(HeirloomColor.rose)
                                            .textCase(.uppercase)

                                        Text(moral)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(HeirloomColor.plum.opacity(0.95))
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(HeirloomColor.polaroidFrame.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding(18)
                        .background(HeirloomColor.polaroidPhoto)
                        .padding(8)
                        .background(HeirloomColor.polaroidFrame)
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.2), radius: 3, x: 4, y: 5)

                        // MARK: - Grok Imagine Controls
                        VStack(spacing: 12) {
                            HStack {
                                Text("Artwork Style")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(HeirloomColor.tabLabel)
                                    .textCase(.uppercase)
                                Spacer()
                            }

                            Picker("Style", selection: $selectedStyle) {
                                Text("Storybook Watercolor").tag("childrens_storybook")
                                Text("Vintage Polaroid").tag("vintage_polaroid")
                            }
                            .pickerStyle(.segmented)

                            Button {
                                Task { await generateIllustration() }
                            } label: {
                                HStack(spacing: 8) {
                                    if isGenerating {
                                        ProgressView()
                                            .tint(.white)
                                        Text("Illustrating with Grok Imagine...")
                                    } else {
                                        Image(systemName: "sparkles")
                                        Text(currentStory.imageUrl != nil ? "Regenerate Storybook Art" : "Illustrate Picture Book")
                                    }
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(HeirloomColor.rose)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: .black.opacity(0.2), radius: 3, x: 2, y: 3)
                            }
                            .disabled(isGenerating)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(16)
                        .background(HeirloomColor.polaroidPhoto.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Children's Picture Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        stopSpeech()
                        dismiss()
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(HeirloomColor.plum)
                }
            }
            .task {
                // If story has no illustration yet, kick off automatic generation on first open!
                if currentStory.imageUrl == nil && !isGenerating {
                    await generateIllustration()
                }
            }
            .onDisappear {
                stopSpeech()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var illustrationSection: some View {
        if let imageUrl = currentStory.imageUrl, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    loadingIllustrationCard
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(HeirloomColor.labelBorder.opacity(0.4), lineWidth: 1.5)
                        )
                case .failure:
                    failedIllustrationCard
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4/3, contentMode: .fit)
        } else if isGenerating {
            loadingIllustrationCard
                .frame(maxWidth: .infinity)
                .frame(height: 240)
        } else {
            promptToIllustrateCard
                .frame(maxWidth: .infinity)
                .frame(height: 220)
        }
    }

    private var loadingIllustrationCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(HeirloomColor.rose)

            VStack(spacing: 4) {
                Text("Grok Imagine is Illustrating...")
                    .font(.heirloomDisplay(18, relativeTo: .headline))
                    .foregroundStyle(HeirloomColor.plum)

                Text("Turning this family memory into a magical storybook page")
                    .font(.caption)
                    .foregroundStyle(HeirloomColor.tabLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HeirloomColor.polaroidFrame.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var failedIllustrationCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(HeirloomColor.rose)

            Text("Illustration not available")
                .font(.headline)
                .foregroundStyle(HeirloomColor.plum)

            Text("Tap Regenerate below to illustrate with Grok Imagine")
                .font(.caption)
                .foregroundStyle(HeirloomColor.tabLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HeirloomColor.polaroidFrame.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var promptToIllustrateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 44))
                .foregroundStyle(HeirloomColor.rose)

            Text("No Picture Book Illustration Yet")
                .font(.heirloomDisplay(18, relativeTo: .headline))
                .foregroundStyle(HeirloomColor.plum)

            Text("Tap 'Illustrate Picture Book' below to create a children's book illustration with Grok Imagine.")
                .font(.caption)
                .foregroundStyle(HeirloomColor.tabLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HeirloomColor.polaroidFrame.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Helpers

    private var displayStoryText: String {
        if let text = currentStory.childrenBookText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return currentStory.narrativeSummary
    }

    private var defaultMoral: String? {
        "Every family memory is a bridge of love, connecting children to where they come from."
    }

    private var subtitle: String? {
        let parts = [currentStory.extractedEra, currentStory.location]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private func generateIllustration() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let updated = try await archive.generateStorybook(for: currentStory._id, style: selectedStyle)
            currentStory = updated
        } catch {
            errorMessage = "Generation note: \(error.localizedDescription)"
        }
    }

    private func toggleSpeech() {
        if isSpeaking {
            stopSpeech()
        } else {
            startSpeech()
        }
    }

    private func startSpeech() {
        stopSpeech()
        let utterance = AVSpeechUtterance(string: "\(currentStory.title). \(displayStoryText). Lesson: \(currentStory.childrenMoral ?? "")")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9 // slightly slower, warm storytelling pace
        utterance.pitchMultiplier = 1.05

        speechSynthesizer.speak(utterance)
        isSpeaking = true
    }

    private func stopSpeech() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }
}
