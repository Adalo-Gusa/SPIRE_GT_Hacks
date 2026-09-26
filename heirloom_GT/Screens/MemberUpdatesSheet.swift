import SwiftUI

/// Presented when tapping a family member's photo on the Home Corkboard tree.
/// Displays their profile details and recent updates (Instagram posts, in-app moments, oral stories).
struct MemberUpdatesSheet: View {
    let member: MemberDocument
    var onNavigateToFeed: () -> Void = {}
    var onNavigateToStory: ((StoryDocument) -> Void)? = nil

    @EnvironmentObject private var archive: FamilyArchive
    @Environment(\.dismiss) private var dismiss

    init(
        member: MemberDocument,
        onNavigateToFeed: @escaping () -> Void = {},
        onNavigateToStory: ((StoryDocument) -> Void)? = nil
    ) {
        self.member = member
        self.onNavigateToFeed = onNavigateToFeed
        self.onNavigateToStory = onNavigateToStory
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. Member Profile Header Card
                    memberHeaderCard

                    // 2. Recent Updates Section
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Recent Updates & Stories")
                                .font(.heirloomDisplay(20, relativeTo: .title3))
                                .foregroundStyle(HeirloomColor.plum)

                            Spacer()

                            let count = memberUpdates.count
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(HeirloomColor.board)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(HeirloomColor.plum, in: Capsule())
                            }
                        }

                        if memberUpdates.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.largeTitle)
                                    .foregroundStyle(HeirloomColor.tabLabel)
                                Text("No recent updates yet")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(HeirloomColor.plum)
                                Text("When \(member.name) posts to the feed or records a story with Loomie, updates appear here.")
                                    .font(.caption)
                                    .foregroundStyle(HeirloomColor.tabLabel)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .padding(.horizontal, 20)
                            .background(HeirloomColor.polaroidFrame.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(memberUpdates) { item in
                                    updateItemCard(item: item)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
            .background { CorkboardBackground() }
            .navigationTitle(member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(HeirloomColor.plum.opacity(0.8))
                    }
                }
            }
            .onAppear {
                // Clear unread badge for this member
                archive.markUpdatesRead(for: member._id)
            }
        }
    }

    private var memberUpdates: [MemberUpdateItem] {
        archive.updates(for: member._id)
    }

    // MARK: - Header Card

    private var memberHeaderCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                // Polaroid Avatar Well
                if let avatar = member.avatarUrl, let url = URL(string: avatar) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            Circle().fill(HeirloomColor.polaroidPhoto)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(HeirloomColor.labelBorder, lineWidth: 2))
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 2, y: 3)
                } else {
                    Circle()
                        .fill(HeirloomColor.rose.opacity(0.2))
                        .frame(width: 72, height: 72)
                        .overlay {
                            Text(String(member.name.prefix(1)))
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(HeirloomColor.plum)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(member.name)
                        .font(.heirloomDisplay(22, relativeTo: .title3))
                        .foregroundStyle(HeirloomColor.plum)

                    HStack(spacing: 6) {
                        Text("Generation \(member.generationTier)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(generationBadgeColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(generationBadgeColor)

                        Text("b. \(String(member.birthYear))")
                            .font(.caption)
                            .foregroundStyle(HeirloomColor.tabLabel)
                    }

                    if let bio = member.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.caption)
                            .foregroundStyle(HeirloomColor.plum.opacity(0.85))
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }

                Spacer()
            }

            // Passions / Hobbies row
            if !member.passions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(member.passions, id: \.self) { passion in
                            Text(passion)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(HeirloomColor.tabLabel)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(HeirloomColor.polaroidPhoto, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(HeirloomColor.polaroidFrame)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 3, x: 4, y: 4)
    }

    // MARK: - Update Item Card

    @ViewBuilder
    private func updateItemCard(item: MemberUpdateItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HeirloomColor.plum)

                Spacer()

                Text(item.date.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(HeirloomColor.tabLabel)

                if item.isUnread {
                    Circle()
                        .fill(HeirloomColor.rose)
                        .frame(width: 8, height: 8)
                }
            }

            Text(item.subtitle)
                .font(.body)
                .foregroundStyle(HeirloomColor.plum.opacity(0.9))
                .lineLimit(3)

            HStack {
                Spacer()

                switch item.type {
                case .post:
                    Button {
                        dismiss()
                        onNavigateToFeed()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Open in Family Feed")
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HeirloomColor.rose)
                    }

                case .story(let story):
                    Button {
                        dismiss()
                        onNavigateToStory?(story)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Read in Notebook")
                            Image(systemName: "book.fill")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HeirloomColor.notebookPlum)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(HeirloomColor.polaroidPhoto)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(2)
        .background(HeirloomColor.polaroidFrame)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.18), radius: 2, x: 3, y: 3)
    }

    private var generationBadgeColor: Color {
        switch member.generationTier {
        case 1: return HeirloomColor.notebookPlum
        case 2: return HeirloomColor.rose
        case 3: return HeirloomColor.tabLabel
        default: return HeirloomColor.plum
        }
    }
}
