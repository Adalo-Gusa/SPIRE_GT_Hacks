import SwiftUI

/// A picture in the family photo album: the photo from a feed post or a story, with its caption.
struct AlbumPhoto: Identifiable {
    enum Source {
        case remote(URL)
        /// A file in the App Group container (posts made in the app or shared from Instagram).
        case local(fileName: String)
    }

    let id: String
    let source: Source
    let caption: String
    /// Who it's from and when, shown under the caption when the photo is opened.
    let byline: String
    let date: Date

    /// Nil when there's no picture to show.
    init?(id: String, imageUrl: String?, caption: String, byline: String, date: Date) {
        guard let imageUrl = imageUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !imageUrl.isEmpty else {
            return nil
        }
        if let url = AppConfiguration.resolvedImageURL(imageUrl) {
            source = .remote(url)
        } else {
            source = .local(fileName: imageUrl)
        }
        self.id = id
        self.caption = caption
        self.byline = byline
        self.date = date
    }
}

extension FamilyArchive {
    /// Every post picture and story photo, newest first.
    var albumPhotos: [AlbumPhoto] {
        let posts = feedPosts.compactMap { post in
            AlbumPhoto(
                id: "post_" + post.id,
                imageUrl: post.imageUrl,
                caption: post.content.isEmpty ? post.authorName : post.content,
                byline: post.authorName,
                date: post.createdAt)
        }
        let storyPhotos = stories.compactMap { story in
            AlbumPhoto(
                id: "story_" + story.id,
                imageUrl: story.imageUrl,
                caption: story.title,
                byline: members.first { $0._id == story.authorId }?.name ?? "Family story",
                date: story.createdAt ?? .distantPast)
        }
        return (posts + storyPhotos).sorted { $0.date > $1.date }
    }
}

/// The Photo Album record: family post pictures and story photos as captioned polaroids.
/// Tapping one opens it larger with its full caption.
struct PhotoAlbumView: View {
    @EnvironmentObject private var archive: FamilyArchive
    @State private var openPhoto: AlbumPhoto?

    private static let spacing: CGFloat = 16

    var body: some View {
        let photos = archive.albumPhotos

        GeometryReader { proxy in
            let cardWidth = (proxy.size.width - Self.spacing * 3) / 2

            ScrollView {
                if photos.isEmpty {
                    ContentUnavailableView {
                        Label("No Photos Yet", systemImage: RecordBook.photoAlbum.systemImage)
                    } description: {
                        Text("Photos from family posts and stories will show up here.")
                    }
                    .foregroundStyle(HeirloomColor.plum)
                    .padding(.top, 80)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.fixed(cardWidth), spacing: Self.spacing), GridItem(.fixed(cardWidth))],
                        spacing: Self.spacing + 8
                    ) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            Button {
                                openPhoto = photo
                            } label: {
                                AlbumPolaroid(photo: photo, width: cardWidth)
                                    // A slight, alternating tilt so the page reads as a scrapbook, not a grid.
                                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -2 : 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Self.spacing)
                }
            }
            .refreshable { await archive.refresh() }
        }
        .background { CorkboardBackground() }
        .navigationTitle(RecordBook.photoAlbum.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openPhoto) { photo in
            AlbumPhotoDetail(photo: photo)
                .presentationDetents([.large])
                .presentationBackground(HeirloomColor.board)
        }
    }
}

/// A `PolaroidCard` scaled to a grid column.
private struct AlbumPolaroid: View {
    let photo: AlbumPhoto
    let width: CGFloat

    var body: some View {
        let scale = width / PolaroidCard.size.width
        AlbumImageLoader(source: photo.source) { image, url in
            PolaroidCard(image: image, imageURL: url, caption: photo.caption)
        }
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: width, height: PolaroidCard.size.height * scale, alignment: .topLeading)
    }
}

/// The opened photo: the whole picture with its full caption, who shared it, and when.
private struct AlbumPhotoDetail: View {
    let photo: AlbumPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AlbumImageLoader(source: photo.source) { image, url in
                        Group {
                            if let image {
                                image.resizable().scaledToFit()
                            } else if let url {
                                AsyncImage(url: url) { phase in
                                    if let loaded = phase.image {
                                        loaded.resizable().scaledToFit()
                                    } else {
                                        HeirloomColor.polaroidPhoto.frame(height: 280)
                                    }
                                }
                            } else {
                                HeirloomColor.polaroidPhoto.frame(height: 280)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Text(photo.caption)
                        .font(.heirloomDisplay(22, relativeTo: .title3))
                        .foregroundStyle(HeirloomColor.plum)

                    Text("\(photo.byline) · \(photo.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(HeirloomColor.tabLabel)
                }
                .padding(14)
                .background(HeirloomColor.polaroidFrame)
                .compositingGroup()
                .shadow(color: .black.opacity(0.25), radius: 3, x: 5, y: 5)
                .padding(18)
            }
            .background { CorkboardBackground() }
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
        }
    }
}

/// Hands its content either a remote URL, or a local photo once it has been read and decoded off the main
/// thread, so scrolling the album doesn't stall on disk reads.
private struct AlbumImageLoader<Content: View>: View {
    let source: AlbumPhoto.Source
    @ViewBuilder var content: (Image?, URL?) -> Content

    @State private var localImage: UIImage?

    var body: some View {
        switch source {
        case .remote(let url):
            content(nil, url)
        case .local(let fileName):
            content(localImage.map { Image(uiImage: $0) }, nil)
                .task(id: fileName) {
                    localImage = await Task.detached(priority: .userInitiated) {
                        AppGroupStorage.shared.loadImageData(named: fileName).flatMap(UIImage.init(data:))
                    }.value
                }
        }
    }
}

#Preview {
    NavigationStack {
        PhotoAlbumView()
    }
    .environmentObject(FamilyArchive())
}
