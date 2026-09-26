import SwiftUI

/// Functional storybook stand-in; replace with the Figma scene cards.
struct PlaceholderStorybookView: View {
    let viewModel: StorybookViewModel

    var body: some View {
        NavigationStack {
            List(viewModel.chapters) { chapter in
                VStack(alignment: .leading, spacing: 8) {
                    AsyncImage(url: chapter.illustrationURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Rectangle()
                            .fill(.quaternary)
                            .aspectRatio(4 / 3, contentMode: .fit)
                    }
                    Text(chapter.title).font(.headline)
                    Text(chapter.narrativeText)
                    Button("New illustration") {
                        Task { await viewModel.regenerateIllustration(for: chapter) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.regeneratingChapterIDs.contains(chapter.id))
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                } else if let message = viewModel.errorMessage, viewModel.chapters.isEmpty {
                    ContentUnavailableView("Storybook unavailable", systemImage: "book.closed", description: Text(message))
                }
            }
            .navigationTitle("Storybook")
            .toolbar {
                Button("Weave") {
                    Task { await viewModel.load() }
                }
                .disabled(viewModel.isLoading)
            }
            .task {
                if viewModel.chapters.isEmpty {
                    await viewModel.load()
                }
            }
        }
    }
}

#Preview {
    PlaceholderStorybookView(viewModel: AppContainer.preview().storybookViewModel)
}
