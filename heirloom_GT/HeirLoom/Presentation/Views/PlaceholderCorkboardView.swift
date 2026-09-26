import SwiftUI

/// Functional stand-in for the spatial corkboard canvas; replace with the Figma design.
struct PlaceholderCorkboardView: View {
    let viewModel: CorkboardViewModel
    let sparkViewModel: SparkNotificationViewModel
    let onSparkAction: (LoomSpark) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let message = sparkViewModel.errorMessage {
                    Section {
                        Text(message).foregroundStyle(.red)
                    }
                }

                sparksSection

                ForEach(viewModel.membersByTier, id: \.tier) { group in
                    Section(group.tier.displayName) {
                        ForEach(group.members) { member in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(member.name).font(.headline)
                                Text(member.passionTags.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Kinship") {
                    ForEach(viewModel.graph.kinshipEdges) { edge in
                        Text("\(viewModel.name(for: edge.fromID)) is \(edge.relationType.rawValue) of \(viewModel.name(for: edge.toID))")
                    }
                }

                Section("Interest bridges") {
                    ForEach(viewModel.graph.hobbyConnections) { connection in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(viewModel.name(for: connection.fromMemberID)) ↔ \(viewModel.name(for: connection.toMemberID))")
                                .font(.headline)
                            Text(connection.sharedInterest)
                            Text(connection.matchRationale)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Memories") {
                    ForEach(viewModel.graph.memories) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(viewModel.name(for: memory.authorID)) · \(memory.extractedEra)")
                                .font(.headline)
                            Text(memory.narrativeSummary)
                        }
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                } else if let message = viewModel.errorMessage, viewModel.graph.members.isEmpty {
                    ContentUnavailableView {
                        Label("Family board unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") {
                            Task { await viewModel.refresh() }
                        }
                    }
                }
            }
            .navigationTitle("Corkboard")
            .toolbar {
                if viewModel.canSimulateDemo {
                    Button("Simulate radio story") {
                        Task { await viewModel.simulateRadioStory() }
                    }
                    .disabled(viewModel.isSimulating)
                }
            }
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.observeGraph() }
        }
    }

    @ViewBuilder
    private var sparksSection: some View {
        let sparks = sparkViewModel.pendingSparks
        if !sparks.isEmpty {
            Section("Sparks for you") {
                ForEach(sparks) { spark in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(spark.promptText)
                        HStack {
                            Button(spark.actionType.callToAction) {
                                onSparkAction(spark)
                            }
                            Spacer()
                            Button("Dismiss", role: .cancel) {
                                Task { await sparkViewModel.dismiss(spark) }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

#Preview {
    let container = AppContainer.preview()
    return PlaceholderCorkboardView(
        viewModel: container.corkboardViewModel,
        sparkViewModel: container.sparkViewModel,
        onSparkAction: { _ in }
    )
}
