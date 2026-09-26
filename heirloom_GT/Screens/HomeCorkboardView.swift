import SwiftUI

/// The home board: draggable polaroids with pins and strings that follow them, on a canvas you can
/// pinch to zoom, drag to pan, and double-tap to focus a photo or fit everything.
/// The pinch itself is recognized by the screen that hosts the board (see `MainTabView`), which drives `cameraController`.
struct HomeCorkboardView: View {
    static let boardSpace = "corkboard"

    var cameraController: BoardCameraController
    /// Opens the family feed from the floating camera button.
    var onOpenFeed: () -> Void = {}

    @State private var board = CorkboardModel.sample()
    @State private var panStart: (pan: CGSize, translation: CGSize)?

    private var camera: BoardCamera {
        get { cameraController.camera }
        nonmutating set { cameraController.camera = newValue }
    }

    var body: some View {
        // The outer reader respects the safe area so the feed button can sit just below the status bar.
        GeometryReader { outer in
            board(topInset: outer.safeAreaInsets.top)
        }
    }

    private func board(topInset: CGFloat) -> some View {
        GeometryReader { proxy in
            let viewport = proxy.size
            let baseScale = viewport.width / CorkboardModel.designWidth
            let scale = baseScale * camera.zoom
            let toScreen = { (point: CGPoint) in
                CGPoint(x: point.x * scale + camera.pan.width, y: point.y * scale + camera.pan.height)
            }

            ZStack {
                CorkboardBackground(spacing: 72 * scale, origin: toScreen(CGPoint(x: 4, y: 34)))
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy) { camera = fitAllCamera(viewport: viewport, baseScale: baseScale) }
                    }

                ForEach(board.photos) { photo in
                    DraggablePolaroid(
                        photo: photo,
                        board: board,
                        center: toScreen(photo.center),
                        scale: scale,
                        isZooming: cameraController.isPinching
                    ) {
                        withAnimation(.snappy) {
                            camera = focusCamera(on: photo, viewport: viewport, baseScale: baseScale)
                        }
                    }
                }

                // Strings and pins stay above the photos so connections are always visible.
                ForEach(board.connections) { connection in
                    if let ends = board.endpoints(of: connection) {
                        BoardString(
                            from: toScreen(ends.from),
                            to: toScreen(ends.to),
                            color: connection.color,
                            curve: connection.curve,
                            lineWidth: 5 * scale)
                    }
                }

                ForEach(board.pins) { pin in
                    if let location = board.location(of: pin) {
                        Pushpin(color: pin.color)
                            .pinned(at: toScreen(location), tilt: board.tilt(of: pin), scale: scale)
                            .allowsHitTesting(false)
                    }
                }

                FeedButton(action: onOpenFeed)
                    .padding(.top, topInset)
                    .padding(.leading, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: viewport.width, height: viewport.height)
            .coordinateSpace(.named(Self.boardSpace))
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

private struct DraggablePolaroid: View {
    let photo: BoardPhoto
    let board: CorkboardModel
    /// Screen position of the photo's center.
    let center: CGPoint
    /// Screen points per board unit (layout scale × zoom).
    let scale: CGFloat
    let isZooming: Bool
    var onDoubleTap: () -> Void

    @State private var dragStart: (center: CGPoint, translation: CGSize)?

    var body: some View {
        PolaroidCard(image: photo.imageName.map { Image($0) }, caption: photo.caption)
            .contentShape(Rectangle())
            .scaleEffect(scale)
            .rotationEffect(photo.rotation)
            .onTapGesture(count: 2, perform: onDoubleTap)
            // Measure the drag in the board's space: the card's own space is scaled, rotated and moves
            // with the finger, which feeds back into the translation and makes the card jitter.
            .gesture(
                DragGesture(coordinateSpace: .named(HomeCorkboardView.boardSpace))
                    .onChanged { value in
                        // A second finger turns this into a pinch; resume from wherever the photo is afterwards.
                        guard !isZooming else {
                            dragStart = nil
                            return
                        }
                        if dragStart == nil {
                            dragStart = (photo.center, value.translation)
                            // No animation: an animated reorder would also animate the first few moves.
                            board.bringToFront(photo.id)
                        }
                        guard let start = dragStart else { return }
                        board.movePhoto(photo.id, to: CGPoint(
                            x: start.center.x + (value.translation.width - start.translation.width) / scale,
                            y: start.center.y + (value.translation.height - start.translation.height) / scale))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .position(center)
            .accessibilityHint("Drag to move. Double-tap to zoom in.")
    }
}

#Preview {
    ZStack {
        CorkboardBackground()
        HomeCorkboardView(cameraController: BoardCameraController())
    }
}
