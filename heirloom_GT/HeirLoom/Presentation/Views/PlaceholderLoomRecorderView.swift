import SwiftUI

/// Functional push-to-talk stand-in; replace with the Figma recorder and waveform.
struct PlaceholderLoomRecorderView: View {
    @Bindable var viewModel: LoomVoiceViewModel
    let members: [FamilyMember]

    @State private var isPressing = false
    @State private var replyDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                if !members.isEmpty {
                    Section("Storyteller") {
                        Picker("Author", selection: $viewModel.authorID) {
                            ForEach(members) { member in
                                Text(member.name).tag(member.id)
                            }
                        }
                        .disabled(viewModel.isRecording || viewModel.state == .processing)
                    }
                }

                Section("Record") {
                    ProgressView(value: Double(viewModel.meterLevel))
                    Text(statusText)
                        .foregroundStyle(.secondary)
                    pushToTalkButton
                    if viewModel.isRecording {
                        Button("Cancel recording", role: .destructive) {
                            Task { await viewModel.cancelRecording() }
                        }
                    }
                    if viewModel.canRetrySave {
                        Button("Try saving again") {
                            Task { await viewModel.retrySave() }
                        }
                    }
                }

                if !viewModel.transcript.isEmpty {
                    Section("Transcript") {
                        Text(viewModel.transcript)
                    }
                }

                if let result = viewModel.lastIngestion {
                    Section("Extracted memory") {
                        Text(result.memory.narrativeSummary)
                        LabeledContent("Era", value: result.memory.extractedEra)
                        LabeledContent("Hobbies", value: result.memory.hobbiesIdentified.joined(separator: ", "))
                        if !result.sparks.isEmpty {
                            LabeledContent("Sparks sent", value: "\(result.sparks.count)")
                        }
                    }
                }

                if !viewModel.followUpQuestions.isEmpty {
                    Section("Loom asks") {
                        ForEach(viewModel.followUpQuestions, id: \.self) { question in
                            Button(question) { viewModel.sendFollowUp(question) }
                                .disabled(viewModel.isStreamingReply)
                        }
                    }
                }

                if viewModel.state == .reviewing {
                    Section("Reply to Loom") {
                        TextField("Say more…", text: $replyDraft, axis: .vertical)
                        Button("Send") {
                            viewModel.sendFollowUp(replyDraft)
                            replyDraft = ""
                        }
                        .disabled(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isStreamingReply)
                        if viewModel.isStreamingReply && viewModel.agentReply.isEmpty {
                            ProgressView()
                        }
                        if !viewModel.agentReply.isEmpty {
                            Text(viewModel.agentReply)
                        }
                        if let replyError = viewModel.replyError {
                            Text(replyError).foregroundStyle(.red)
                        }
                    }

                    Button("Record another story") { viewModel.reset() }
                }
            }
            .navigationTitle("Loom")
        }
    }

    private var pushToTalkButton: some View {
        Text(viewModel.isRecording ? "Release to finish" : "Hold to talk")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressing else { return }
                        isPressing = true
                        Task { await viewModel.beginPushToTalk() }
                    }
                    .onEnded { _ in
                        isPressing = false
                        Task { await viewModel.endPushToTalk() }
                    }
            )
            .disabled(viewModel.state == .processing)
            .accessibilityAddTraits(.isButton)
    }

    private var statusText: String {
        switch viewModel.state {
        case .idle: "Ready"
        case .recording: "Listening…"
        case .processing: "Weaving your story…"
        case .reviewing: "Memory saved"
        case .failed(let message): message
        }
    }
}

#Preview {
    PlaceholderLoomRecorderView(
        viewModel: AppContainer.preview().loomVoiceViewModel,
        members: MockDataService.seededGraph().members
    )
}
