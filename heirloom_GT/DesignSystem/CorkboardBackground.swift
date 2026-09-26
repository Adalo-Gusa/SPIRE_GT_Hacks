import SwiftUI

/// The tan grid-paper board that sits behind every HeirLoom screen.
struct CorkboardBackground: View {
    var spacing: CGFloat = 72
    /// Any point a grid line crosses; move it to pan the grid.
    var origin = CGPoint(x: 4, y: 34)
    var lineColor: Color = HeirloomColor.gridLine

    var body: some View {
        Canvas { context, size in
            let spacing = max(spacing, 6)
            let startX = origin.x - (origin.x / spacing).rounded(.down) * spacing
            let startY = origin.y - (origin.y / spacing).rounded(.down) * spacing
            var grid = Path()
            for x in stride(from: startX, through: size.width, by: spacing) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: startY, through: size.height, by: spacing) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(lineColor), lineWidth: 2)
        }
        .background(HeirloomColor.board)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview {
    CorkboardBackground()
}
