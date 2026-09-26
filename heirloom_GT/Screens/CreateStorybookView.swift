import SwiftUI

/// The Create Story Book page: groups all family notebook stories into an illustrated storybook
/// with Grok Imagine picture generation to pass down family memories to children.
struct CreateStorybookView: View {
    @EnvironmentObject private var archive: FamilyArchive
    @Environment(\.tabBarTop) private var tabBarTop

    enum GroupingMode: String, CaseIterable, Identifiable {
        case storyteller = "By Storyteller"
        case era = "By Era"
        case all = "All Chapters"

        var id: String { rawValue }
    }

    @State private var groupingMode: GroupingMode = .storyteller
    @State private var activeStoryForBook: StoryDocument?

    var body: some View {
        GeometryReader { proxy in
            let bottomClearance = tabBarTop.map { max(0, proxy.frame(in: .global).maxY - $0) + 16 } ?? 24

            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Storybook Hero Banner
                    storybookHeaderBanner

                    // MARK: - Grouping Selector
                    Picker("Grouping", selection: $groupingMode) {
                        ForEach(GroupingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)

                    // MARK: - Grouped Story Chapters
                    if archive.stories.isEmpty {
                        emptyStateView
                    } else {
                        groupedStoriesContent
                            .padding(.horizontal, 20)
                            .padding(.bottom, bottomClearance)
                    }
                }
                .padding(.top, 10)
            }
            .refreshable { await archive.refresh() }
        }
        .background { CorkboardBackground() }
        .navigationTitle("Create a Storybook")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeStoryForBook) { story in
            ChildrenPictureBookModal(story: story)
                .environmentObject(archive)
        }
    }

    // MARK: - Header Banner

    private var storybookHeaderBanner: some View {
        HStack(spacing: 16) {
            Image("BookStorybook")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 95)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 3, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Family Storybook")
                    .font(.heirloomDisplay(24, relativeTo: .title2))
                    .foregroundStyle(HeirloomColor.plum)

                Text("Passing down generations of wisdom and laughter to children through illustrated picture books.")
                    .font(.caption)
                    .foregroundStyle(HeirloomColor.tabLabel)
                    .lineLimit(3)

                let illustratedCount = archive.stories.filter { $0.imageUrl != nil }.count
                HStack(spacing: 8) {
                    Label("\(archive.stories.count) Memories", systemImage: "book.closed")
                    Text("·")
                    Label("\(illustratedCount) Illustrated", systemImage: "sparkles")
                        .foregroundStyle(HeirloomColor.rose)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(HeirloomColor.plumMuted)
            }
            Spacer()
        }
        .padding(16)
        .background(HeirloomColor.polaroidPhoto)
        .padding(6)
        .background(HeirloomColor.polaroidFrame)
        .compositingGroup()
        .shadow(color: .black.opacity(0.2), radius: 3, x: 4, y: 4)
        .padding(.horizontal, 20)
    }

    // MARK: - Grouped Content

    @ViewBuilder
    private var groupedStoriesContent: some View {
        switch groupingMode {
        case .storyteller:
            let groups = Dictionary(grouping: archive.stories, by: { authorName(for: $0.authorId) })
            ForEach(groups.keys.sorted(), id: \.self) { author in
                if let stories = groups[author] {
                    sectionView(title: author, icon: "person.crop.circle.fill", stories: stories)
                }
            }

        case .era:
            let groups = Dictionary(grouping: archive.stories, by: { $0.extractedEra ?? "Timeless Memories" })
            ForEach(groups.keys.sorted(), id: \.self) { era in
                if let stories = groups[era] {
                    sectionView(title: era, icon: "clock.arrow.circlepath", stories: stories)
                }
            }

        case .all:
            LazyVStack(spacing: 18) {
                ForEach(archive.stories) { story in
                    StorybookChapterCard(story: story) {
                        activeStoryForBook = story
                    }
                }
            }
        }
    }

    private func sectionView(title: String, icon: String, stories: [StoryDocument]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(HeirloomColor.rose)
                Text(title)
                    .font(.heirloomDisplay(20, relativeTo: .headline))
                    .foregroundStyle(HeirloomColor.plum)
                Spacer()
                Text("\(stories.count) stories")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HeirloomColor.tabLabel)
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)

            LazyVStack(spacing: 18) {
                ForEach(stories) { story in
                    StorybookChapterCard(story: story) {
                        activeStoryForBook = story
                    }
                }
            }
        }
    }

    private func authorName(for authorId: String) -> String {
        if let member = archive.members.first(where: { $0._id == authorId }) {
            return member.name
        }
        if authorId.contains("joe") { return "Grandpa Joe Clarke" }
        if authorId.contains("beatrice") { return "Aunt Beatrice Clarke" }
        if authorId.contains("marcus") { return "Marcus Clarke" }
        return "Family Stories"
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No stories to compile yet", systemImage: "book.closed")
        } description: {
            Text("Record family memories with Loomie from the Home corkboard, and they will be grouped here into your family picture book!")
        }
        .foregroundStyle(HeirloomColor.plum)
        .padding(.top, 60)
    }
}

/// One storybook chapter card displaying memory summary, illustration preview,
/// and the top-right Grok Imagine sparkle icon button.
struct StorybookChapterCard: View {
    let story: StoryDocument
    let onOpenBook: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Card Header: Title & Top-Right Grok Imagine Icon
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(story.title)
                        .font(.heirloomDisplay(21, relativeTo: .title3))
                        .foregroundStyle(HeirloomColor.plum)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HeirloomColor.tabLabel)
                    }
                }

                Spacer()

                // MARK: - Top Right Grok Imagine Icon
                Button {
                    onOpenBook()
                } label: {
                    ZStack {
                        Circle()
                            .fill(story.imageUrl != nil ? HeirloomColor.rose : HeirloomColor.polaroidFrame)
                            .frame(width: 36, height: 36)
                            .shadow(color: .black.opacity(0.18), radius: 2, x: 1, y: 2)

                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(story.imageUrl != nil ? .white : HeirloomColor.rose)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Illustrate story with Grok Imagine")
            }

            // MARK: - Illustrated Thumbnail Preview (if already generated)
            if let imageUrl = story.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        ZStack(alignment: .bottomTrailing) {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: 140)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            // Illustrated Edition Ribbon
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("Grok Imagine Edition")
                                    .font(.caption2.weight(.bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(HeirloomColor.plum.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .padding(8)
                        }
                    default:
                        EmptyView()
                    }
                }
            }

            // MARK: - Narrative / Children Book Summary
            Text(story.childrenBookText ?? story.narrativeSummary)
                .font(.body)
                .foregroundStyle(HeirloomColor.plum.opacity(0.9))
                .lineLimit(4)

            // MARK: - Action Footer
            HStack {
                if !story.passions.isEmpty {
                    Text(story.passions.prefix(2).joined(separator: " · "))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HeirloomColor.tabLabel)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(HeirloomColor.polaroidFrame.opacity(0.6), in: Capsule())
                }

                Spacer()

                Button {
                    onOpenBook()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: story.imageUrl != nil ? "book.fill" : "wand.and.stars")
                        Text(story.imageUrl != nil ? "Open Picture Book" : "Create Picture Book")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(story.imageUrl != nil ? HeirloomColor.rose : HeirloomColor.notebookPlum)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeirloomColor.polaroidPhoto)
        .padding(8)
        .background(HeirloomColor.polaroidFrame)
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 2, x: 4, y: 5)
        .overlay(alignment: .top) {
            Pushpin(showsHole: false)
                .scaleEffect(0.42, anchor: .bottom)
                .frame(height: Pushpin.size.height * 0.42)
                .offset(y: -28)
                .accessibilityHidden(true)
        }
    }

    private var subtitle: String? {
        let parts = [story.extractedEra, story.location]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
