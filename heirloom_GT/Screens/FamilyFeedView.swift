import SwiftUI
import PhotosUI

/// The Family Feed sheet: where shared Instagram posts and in-app family updates live.
/// Includes an in-app composer at the top for sharing moments with photos.
public struct FamilyFeedView: View {
    @EnvironmentObject private var archive: FamilyArchive
    @Environment(\.dismiss) private var dismiss

    // Composer State
    @State private var composerText: String = ""
    @State private var selectedAuthorId: String = "member_alex"
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var isPosting: Bool = false
    @State private var errorMessage: String? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. In-App Composer Card
                    inAppComposerCard

                    // 2. Feed Stream
                    if archive.feedPosts.isEmpty {
                        emptyFeedPlaceholder
                    } else {
                        LazyVStack(spacing: 22) {
                            ForEach(archive.feedPosts) { post in
                                FamilyFeedCard(post: post)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 36)
            }
            .background { CorkboardBackground() }
            .navigationTitle("Family Feed")
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
            .refreshable {
                await archive.refresh()
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        selectedImageData = data
                    }
                }
            }
        }
    }

    // MARK: - In-App Composer Card

    private var inAppComposerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // Author Avatar Picker
                Menu {
                    ForEach(archive.members) { member in
                        Button {
                            selectedAuthorId = member._id
                        } label: {
                            HStack {
                                Text(member.name)
                                if member._id == selectedAuthorId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let member = currentAuthor {
                            Text("Posting as \(member.name)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(HeirloomColor.plum)
                        } else {
                            Text("Posting as Alex Clarke")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(HeirloomColor.plum)
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(HeirloomColor.tabLabel)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(HeirloomColor.polaroidFrame.opacity(0.8), in: Capsule())
                }

                Spacer()

                // Photos Picker Button
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                        Text(selectedImageData != nil ? "Change Photo" : "Add Photo")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HeirloomColor.plum)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(HeirloomColor.polaroidFrame.opacity(0.8), in: Capsule())
                }
            }

            // Attached Photo Preview
            if let imageData = selectedImageData, let uiImage = UIImage(data: imageData) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        selectedPhotoItem = nil
                        selectedImageData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .padding(8)
                }
            }

            // Text Input
            TextField("Share a moment with the family...", text: $composerText, axis: .vertical)
                .lineLimit(3...6)
                .font(.body)
                .foregroundStyle(HeirloomColor.plum)
                .padding(12)
                .background(HeirloomColor.polaroidPhoto, in: RoundedRectangle(cornerRadius: 12))

            // Error display
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Post Button
            HStack {
                Spacer()
                Button {
                    submitPost()
                } label: {
                    HStack(spacing: 6) {
                        if isPosting {
                            ProgressView()
                                .tint(HeirloomColor.board)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.caption.weight(.bold))
                            Text("Post to Feed")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .foregroundStyle(HeirloomColor.board)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(HeirloomColor.plum, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 2, y: 3)
                }
                .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImageData == nil)
                .opacity((composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImageData == nil) ? 0.6 : 1.0)
            }
        }
        .padding(16)
        .background(HeirloomColor.polaroidFrame)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 3, x: 4, y: 4)
    }

    private var emptyFeedPlaceholder: some View {
        ContentUnavailableView {
            Label("No Moments Yet", systemImage: "camera")
        } description: {
            Text("Share an update above, or share an Instagram post into HeirLoom!")
        }
        .foregroundStyle(HeirloomColor.plum)
        .padding(.top, 40)
    }

    private var currentAuthor: MemberDocument? {
        archive.members.first { $0._id == selectedAuthorId }
    }

    private func submitPost() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || selectedImageData != nil else { return }

        isPosting = true
        errorMessage = nil

        let author = currentAuthor
        let authorName = author?.name ?? "Alex Clarke"
        let authorAvatar = author?.avatarUrl

        var imageFilename: String? = nil
        if let data = selectedImageData {
            imageFilename = AppGroupStorage.shared.saveSharedImage(data: data, prefix: "in_app")
        }

        let newPost = FeedPostDocument(
            id: "post_\(UUID().uuidString.prefix(8))",
            familyId: AppConfiguration.mongoDBFamilyId,
            authorId: selectedAuthorId,
            authorName: authorName,
            authorAvatarUrl: authorAvatar,
            content: text,
            imageUrl: imageFilename,
            postUrl: nil,
            source: "in_app",
            passions: [],
            location: nil,
            createdAt: Date(),
            isUnread: true
        )

        Task {
            do {
                try await archive.addFeedPost(newPost)
                composerText = ""
                selectedImageData = nil
                selectedPhotoItem = nil
                isPosting = false
            } catch {
                errorMessage = "Couldn't save: \(error.localizedDescription)"
                isPosting = false
            }
        }
    }
}

// MARK: - Family Feed Card

struct FamilyFeedCard: View {
    let post: FeedPostDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Pushpin & Author Info
            HStack(spacing: 12) {
                // Author Avatar
                if let avatar = post.authorAvatarUrl, let url = URL(string: avatar) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            Circle().fill(HeirloomColor.polaroidPhoto)
                        }
                    }
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(HeirloomColor.labelBorder, lineWidth: 1.5))
                } else {
                    Circle()
                        .fill(HeirloomColor.rose.opacity(0.2))
                        .frame(width: 42, height: 42)
                        .overlay {
                            Text(String(post.authorName.prefix(1)))
                                .font(.headline.weight(.bold))
                                .foregroundStyle(HeirloomColor.plum)
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.heirloomDisplay(18, relativeTo: .headline))
                        .foregroundStyle(HeirloomColor.plum)

                    HStack(spacing: 6) {
                        Text(post.createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(HeirloomColor.tabLabel)

                        if post.source == "instagram" {
                            HStack(spacing: 3) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 9))
                                Text("Instagram")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(HeirloomColor.rose.opacity(0.15), in: Capsule())
                            .foregroundStyle(HeirloomColor.rose)
                        } else {
                            HStack(spacing: 3) {
                                Image(systemName: "bubble.left.fill")
                                    .font(.system(size: 9))
                                Text("Family Moment")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(HeirloomColor.notebookPlum.opacity(0.12), in: Capsule())
                            .foregroundStyle(HeirloomColor.notebookPlum)
                        }
                    }
                }

                Spacer()

                // Small Pushpin accent
                Pushpin(showsHole: false)
                    .scaleEffect(0.35, anchor: .top)
                    .frame(width: 24, height: 24)
            }

            // Post Photo (if present)
            if let imageUrl = post.imageUrl, !imageUrl.isEmpty {
                feedPostImage(imageUrl: imageUrl)
            }

            // Post Content / Caption
            if !post.content.isEmpty {
                Text(post.content)
                    .font(.body)
                    .foregroundStyle(HeirloomColor.plum)
                    .padding(.horizontal, 4)
            }

            // Passions / Tags
            if !post.passions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(post.passions, id: \.self) { passion in
                            Text(passion)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(HeirloomColor.tabLabel)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(HeirloomColor.polaroidPhoto, in: Capsule())
                        }
                    }
                }
            }

            // Instagram External Link Button
            if post.source == "instagram", let postUrl = post.postUrl, let url = URL(string: postUrl) {
                Link(destination: url) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                        Text("View Original on Instagram")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HeirloomColor.rose)
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(HeirloomColor.polaroidFrame)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 3, x: 5, y: 5)
    }

    @ViewBuilder
    private func feedPostImage(imageUrl: String) -> some View {
        if imageUrl.starts(with: "http"), let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 260)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                default:
                    Rectangle()
                        .fill(HeirloomColor.polaroidPhoto)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        } else if let localData = AppGroupStorage.shared.loadImageData(named: imageUrl),
                  let uiImg = UIImage(data: localData) {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 260)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
