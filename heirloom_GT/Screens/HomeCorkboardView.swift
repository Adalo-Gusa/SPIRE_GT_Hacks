import SwiftUI

/// The home board: the family tree as pinned polaroids joined by strings (spouse and parent–child), on a
/// canvas you can pinch to zoom, drag to pan, and double-tap to focus a photo or fit everything.
/// Photos are fixed in place; their layout comes from `CorkboardModel.familyTree(from:)`.
/// The pinch itself is recognized by the screen that hosts the board (see `MainTabView`), which drives `cameraController`.
struct HomeCorkboardView: View {
    static let boardSpace = "corkboard"

    var cameraController: BoardCameraController
    /// Opens the family feed from the floating camera button.
    var onOpenFeed: () -> Void = {}

    @EnvironmentObject private var archive: FamilyArchive
    @State private var board = CorkboardModel()
    /// Bumped whenever the tree is rebuilt, so the camera re-fits the whole tree on screen.
    @State private var fitRequest = 0
    @State private var panStart: (pan: CGSize, translation: CGSize)?
    @State private var selectedMemberForUpdates: MemberDocument? = nil
    /// Set when the member sheet asks for the feed; the feed opens once that sheet has finished dismissing,
    /// since presenting it while the member sheet is still on screen fails and leaves the app unresponsive.
    @State private var opensFeedAfterDismiss = false

    private var camera: BoardCamera {
        get { cameraController.camera }
        nonmutating set { cameraController.camera = newValue }
    }

    var body: some View {
        // The outer reader respects the safe area so the feed button can sit just below the status bar.
        GeometryReader { outer in
            board(topInset: outer.safeAreaInsets.top)
        }
        .task(id: archive.members.map(\.id)) {
            board = CorkboardModel.familyTree(from: archive.members)
            fitRequest += 1
        }
        .sheet(item: $selectedMemberForUpdates, onDismiss: {
            guard opensFeedAfterDismiss else { return }
            opensFeedAfterDismiss = false
            onOpenFeed()
        }) { member in
            MemberUpdatesSheet(
                member: member,
                onNavigateToFeed: {
                    opensFeedAfterDismiss = true
                    selectedMemberForUpdates = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(HeirloomColor.board)
        }
    }

    private func board(topInset: CGFloat) -> some View {
        GeometryReader { proxy in
            let viewport = proxy.size
            let baseScale = viewport.width / CorkboardModel.designWidth
            let scale = baseScale * camera.zoom

            ZStack {
                CorkboardBackground(
                    spacing: 72 * scale,
                    origin: CGPoint(x: 4 * scale + camera.pan.width, y: 34 * scale + camera.pan.height))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy) { camera = fitAllCamera(viewport: viewport, baseScale: baseScale) }
                    }

                // The photos, strings and pins are laid out once at the base scale and zoomed and panned as one
                // layer, so moving the camera doesn't lay out every item on the board again each frame.
                BoardLayer(board: board, baseScale: baseScale) { photo in
                    withAnimation(.snappy) {
                        camera = focusCamera(on: photo, viewport: viewport, baseScale: baseScale)
                    }
                    if let memId = photo.memberId, let member = archive.members.first(where: { $0._id == memId }) {
                        selectedMemberForUpdates = member
                    }
                }
                .equatable()
                .frame(width: viewport.width, height: viewport.height)
                .scaleEffect(camera.zoom, anchor: .topLeading)
                .offset(camera.pan)

                FeedButton(action: onOpenFeed)
                    .padding(.top, topInset)
                    .padding(.leading, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: viewport.width, height: viewport.height)
            .coordinateSpace(.named(Self.boardSpace))
            // Dragging anywhere pans the board, including on a photo (photos themselves don't move).
            .gesture(panGesture)
            .task(id: fitRequest) {
                guard fitRequest > 0, !board.photos.isEmpty else { return }
                camera = fitAllCamera(viewport: viewport, baseScale: baseScale)
            }
            .accessibilityZoomAction { action in
                let factor: CGFloat = action.direction == .zoomIn ? 1.5 : 1 / 1.5
                let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
                withAnimation(.snappy) {
                    camera = camera.zoomed(to: camera.zoom * factor, keeping: center)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(coordinateSpace: .named(Self.boardSpace))
            .onChanged { value in
                // Let the pinch own the camera while two fingers are down; resume panning from wherever it left off.
                guard !cameraController.isPinching else {
                    panStart = nil
                    return
                }
                let start = panStart ?? (camera.pan, value.translation)
                if panStart == nil { panStart = start }
                camera.pan = CGSize(
                    width: start.pan.width + value.translation.width - start.translation.width,
                    height: start.pan.height + value.translation.height - start.translation.height)
            }
            .onEnded { _ in panStart = nil }
    }

    // MARK: - Camera math

    /// Centers `rect` (board units) in the viewport's visible area, as large as fits.
    private func camera(fitting rect: CGRect, viewport: CGSize, baseScale: CGFloat) -> BoardCamera {
        // Leave room for the status bar at the top (the board extends under it).
        let visible = CGRect(x: 0, y: 60, width: viewport.width, height: max(viewport.height - 60, 1)).insetBy(dx: 16, dy: 16)
        let fit = min(visible.width / (rect.width * baseScale), visible.height / (rect.height * baseScale))
        let zoom = min(max(fit, BoardCamera.zoomRange.lowerBound), BoardCamera.zoomRange.upperBound)
        let scale = baseScale * zoom
        return BoardCamera(
            zoom: zoom,
            pan: CGSize(width: visible.midX - rect.midX * scale, height: visible.midY - rect.midY * scale))
    }

    private func fitAllCamera(viewport: CGSize, baseScale: CGFloat) -> BoardCamera {
        guard let bounds = board.photos.map(Self.bounds(of:)).reduce(nil, { $0?.union($1) ?? $1 }) else {
            return BoardCamera()
        }
        return camera(fitting: bounds, viewport: viewport, baseScale: baseScale)
    }

    private func focusCamera(on photo: BoardPhoto, viewport: CGSize, baseScale: CGFloat) -> BoardCamera {
        camera(fitting: Self.bounds(of: photo), viewport: viewport, baseScale: baseScale)
    }

    /// A photo's footprint in board units, including its rotation.
    private static func bounds(of photo: BoardPhoto) -> CGRect {
        let size = PolaroidCard.size
        return CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
            .applying(CGAffineTransform(rotationAngle: photo.rotation.radians))
            .offsetBy(dx: photo.center.x, dy: photo.center.y)
    }
}

/// Everything pinned to the board, positioned in screen points at `baseScale` (before the camera's zoom and pan).
/// Equatable so the camera moving doesn't rebuild it; it still updates when the board or unread counts change.
private struct BoardLayer: View, Equatable {
    let board: CorkboardModel
    /// Screen points per board unit at zoom 1.
    let baseScale: CGFloat
    var onTapPhoto: (BoardPhoto) -> Void

    @EnvironmentObject private var archive: FamilyArchive

    static func == (lhs: BoardLayer, rhs: BoardLayer) -> Bool {
        lhs.board === rhs.board && lhs.baseScale == rhs.baseScale
    }

    var body: some View {
        let toLayer = { (point: CGPoint) in CGPoint(x: point.x * baseScale, y: point.y * baseScale) }

        ZStack {
            ForEach(board.photos) { photo in
                PinnedPolaroid(
                    photo: photo,
                    center: toLayer(photo.center),
                    scale: baseScale,
                    unreadCount: photo.memberId.map { archive.unreadCount(for: $0) } ?? 0,
                    onTap: { onTapPhoto(photo) },
                    onDoubleTap: {}
                )
            }

            // Strings and pins stay above the photos so connections are always visible.
            ForEach(board.connections) { connection in
                if let ends = board.endpoints(of: connection) {
                    BoardString(
                        from: toLayer(ends.from),
                        to: toLayer(ends.to),
                        color: connection.color,
                        curve: connection.curve,
                        lineWidth: 3.5 * baseScale)
                        // A soft shadow lifts the string off the board, like twine held up by its pins.
                        .shadow(color: .black.opacity(0.22), radius: 1.5 * baseScale, x: 2 * baseScale, y: 3 * baseScale)
                }
            }

            ForEach(board.pins) { pin in
                if let location = board.location(of: pin) {
                    Pushpin(color: pin.color)
                        .pinned(at: toLayer(location), tilt: board.tilt(of: pin), scale: baseScale)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// A family member's photo, fixed in place on the board.
/// Displays an iOS-style notification symbol when there are recent updates.
/// Tap opens their recent updates and stories, double-tap zooms in.
private struct PinnedPolaroid: View {
    let photo: BoardPhoto
    /// Screen position of the photo's center.
    let center: CGPoint
    /// Screen points per board unit (layout scale × zoom).
    let scale: CGFloat
    let unreadCount: Int
    var onTap: () -> Void
    var onDoubleTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PolaroidCard(image: photo.imageName.map { Image($0) }, imageURL: photo.imageURL, caption: photo.caption)

            // iOS-style notification badge (shown when there are unread posts / updates)
            if unreadCount > 0 {
                ZStack {
                    Circle()
                        .fill(HeirloomColor.rose)
                    Text("\(unreadCount)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.35), radius: 3, x: 2, y: 3)
                .offset(x: 10, y: -10)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(scale)
        .rotationEffect(photo.rotation)
        .onTapGesture {
            onTap()
        }
        .position(center)
        .accessibilityHint("Tap to see member updates, double-tap to zoom.")
    }
}

#Preview {
    ZStack {
        CorkboardBackground()
        HomeCorkboardView(cameraController: BoardCameraController())
            .environmentObject(FamilyArchive())
    }
}
