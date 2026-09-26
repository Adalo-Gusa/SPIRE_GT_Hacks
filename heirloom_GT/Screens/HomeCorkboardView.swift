import SwiftUI

/// The zoom and pan applied on top of the board's base layout.
struct BoardCamera: Equatable {
    static let zoomRange: ClosedRange<CGFloat> = 0.25...4

    var zoom: CGFloat = 1
    /// Screen offset of the board's origin.
    var pan: CGSize = .zero
}

/// The home board: draggable polaroids with pins and strings that follow them, on a canvas you can
/// pinch to zoom, drag to pan, and double-tap to focus a photo or fit everything.
struct HomeCorkboardView: View {
    static let boardSpace = "corkboard"

    @State private var board = CorkboardModel.sample()
    @State private var camera = BoardCamera()

    @State private var zoomStart: BoardCamera?
    @State private var panStart: (pan: CGSize, translation: CGSize)?

    var body: some View {
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
                        isZooming: zoomStart != nil
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
            }
            .frame(width: viewport.width, height: viewport.height)
            .coordinateSpace(.named(Self.boardSpace))
            .simultaneousGesture(zoomGesture)
            .accessibilityZoomAction { action in
                let factor: CGFloat = action.direction == .zoomIn ? 1.5 : 1 / 1.5
                let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
                withAnimation(.snappy) {
                    camera = zoomed(camera, to: camera.zoom * factor, keeping: center)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Gestures

    private var zoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                let start = zoomStart ?? camera
                if zoomStart == nil { zoomStart = camera }
                camera = zoomed(start, to: start.zoom * value.magnification, keeping: value.startLocation)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private var panGesture: some Gesture {
        DragGesture(coordinateSpace: .named(Self.boardSpace))
            .onChanged { value in
                // Let the pinch own the camera while two fingers are down; resume panning from wherever it left off.
                guard zoomStart == nil else {
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

    /// Zooms from `start` so the board point under `anchor` (a screen point) stays put.
    private func zoomed(_ start: BoardCamera, to newZoom: CGFloat, keeping anchor: CGPoint) -> BoardCamera {
        let zoom = min(max(newZoom, BoardCamera.zoomRange.lowerBound), BoardCamera.zoomRange.upperBound)
        let ratio = zoom / start.zoom
        return BoardCamera(
            zoom: zoom,
            pan: CGSize(
                width: anchor.x - (anchor.x - start.pan.width) * ratio,
                height: anchor.y - (anchor.y - start.pan.height) * ratio))
    }

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

    @State private var dragStart: CGPoint?

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
                        guard !isZooming else { return }
                        if dragStart == nil {
                            dragStart = photo.center
                            // No animation: an animated reorder would also animate the first few moves.
                            board.bringToFront(photo.id)
                        }
                        guard let start = dragStart else { return }
                        board.movePhoto(photo.id, to: CGPoint(
                            x: start.x + value.translation.width / scale,
                            y: start.y + value.translation.height / scale))
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
        HomeCorkboardView()
    }
}
