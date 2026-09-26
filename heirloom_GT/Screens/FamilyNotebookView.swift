import SwiftUI

/// The Family Notebook: every story saved from a Loomie conversation, newest first.
struct FamilyNotebookView: View {
    @EnvironmentObject private var archive: FamilyArchive
    @Environment(\.tabBarTop) private var tabBarTop

    var body: some View {
        GeometryReader { proxy in
            // The page runs under the tab bar; leave room so the last card can scroll above the yarn.
            let bottomClearance = tabBarTop.map { max(0, proxy.frame(in: .global).maxY - $0) + 16 } ?? 24

            ScrollView {
                if archive.stories.isEmpty {
                    ContentUnavailableView {
                        Label("No stories yet", systemImage: "book.closed")
                    } description: {
                        Text("Talk to Loomie from the Home board, then tap Generate story. Stories land here.")
                    }
                    .foregroundStyle(HeirloomColor.plum)
                    .padding(.top, 80)
                } else {
                    LazyVStack(spacing: 18) {
                        ForEach(archive.stories) { story in
                            StoryCard(story: story)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, bottomClearance)
                }
            }
            .refreshable { await archive.refresh() }
        }
        .background { CorkboardBackground() }
        .navigationTitle("Family Notebook")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One story, styled like a note pinned to the board.
private struct StoryCard: View {
    let story: StoryDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(story.title)
                .font(.heirloomDisplay(22, relativeTo: .title3))
                .foregroundStyle(HeirloomColor.plum)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeirloomColor.tabLabel)
            }

            Text(story.narrativeSummary)
                .font(.body)
                .foregroundStyle(HeirloomColor.plum.opacity(0.9))

            if !tags.isEmpty {
                Text(tags.joined(separator: "  ·  "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HeirloomColor.tabLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HeirloomColor.polaroidFrame.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeirloomColor.polaroidPhoto)
        .padding(10)
        .background(HeirloomColor.polaroidFrame)
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 2, x: 5, y: 5)
        .overlay(alignment: .top) {
            Pushpin(showsHole: false)
                .scaleEffect(0.45, anchor: .bottom)
                .frame(height: Pushpin.size.height * 0.45)
                .offset(y: -30)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String? {
        let parts = [story.extractedEra, story.location]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// People and passions from the story.
    private var tags: [String] {
        story.peopleMentioned + story.passions
    }
}
