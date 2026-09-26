import SwiftUI
import Observation

/// The zoom and pan applied on top of the board's base layout.
struct BoardCamera: Equatable {
    static let zoomRange: ClosedRange<CGFloat> = 0.25...4

    var zoom: CGFloat = 1
    /// Screen offset of the board's origin.
    var pan: CGSize = .zero

    /// Zooms from this camera so the board point under `anchor` (a screen point) stays put.
    func zoomed(to newZoom: CGFloat, keeping anchor: CGPoint) -> BoardCamera {
        let zoom = min(max(newZoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let ratio = zoom / self.zoom
        return BoardCamera(
            zoom: zoom,
            pan: CGSize(
                width: anchor.x - (anchor.x - pan.width) * ratio,
                height: anchor.y - (anchor.y - pan.height) * ratio))
    }
}

/// Owns the home board's camera. It lives above the board so the pinch can be recognized over the whole
/// screen, including the tab bar: a pinch whose fingers start on the bar or a button still zooms the board.
@Observable
final class BoardCameraController {
    var camera = BoardCamera()
    private(set) var pinchStart: BoardCamera?

    var isPinching: Bool { pinchStart != nil }

    /// `anchor` is where the pinch started, in the board's coordinate space.
    func pinchChanged(magnification: CGFloat, anchor: CGPoint) {
        let start = pinchStart ?? camera
        if pinchStart == nil { pinchStart = camera }
        camera = start.zoomed(to: start.zoom * magnification, keeping: anchor)
    }

    func pinchEnded() {
        pinchStart = nil
    }
}
