import SwiftUI

/// A shape built from SVG path data exported from Figma, scaled from its view box into the layout rect.
struct SVGPathShape: Shape {
    private let path: Path
    private let viewBox: CGRect

    init(_ data: String, viewBox: CGRect) {
        self.path = SVGPathParser.parse(data)
        self.viewBox = viewBox
    }

    init(_ data: String, viewBox: CGSize) {
        self.init(data, viewBox: CGRect(origin: .zero, size: viewBox))
    }

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / viewBox.width
        let sy = rect.height / viewBox.height
        let transform = CGAffineTransform(translationX: -viewBox.minX, y: -viewBox.minY)
            .concatenating(CGAffineTransform(scaleX: sx, y: sy))
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return path.applying(transform)
    }
}

/// Minimal parser for the absolute commands Figma emits (M, L, H, V, C, Z).
enum SVGPathParser {
    static func parse(_ data: String) -> Path {
        let tokens = tokenize(data)
        var path = Path()
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero

        func number() -> CGFloat {
            defer { index += 1 }
            return CGFloat(Double(tokens[index]) ?? 0)
        }
        func point() -> CGPoint { CGPoint(x: number(), y: number()) }

        while index < tokens.count {
            if let first = tokens[index].first, first.isLetter {
                command = first
                index += 1
            }
            switch command {
            case "M":
                current = point()
                path.move(to: current)
                command = "L" // Extra coordinate pairs after M are implicit line-tos.
            case "L":
                current = point()
                path.addLine(to: current)
            case "H":
                current.x = number()
                path.addLine(to: current)
            case "V":
                current.y = number()
                path.addLine(to: current)
            case "C":
                let control1 = point(), control2 = point()
                current = point()
                path.addCurve(to: current, control1: control1, control2: control2)
            case "Z", "z":
                path.closeSubpath()
                command = "?" // Z takes no arguments; the next token must be a command.
            default:
                assertionFailure("Unsupported SVG path command \(command)")
                return path
            }
        }
        return path
    }

    private static func tokenize(_ data: String) -> [String] {
        let pattern = #"[A-Za-z]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(data.startIndex..., in: data)
        return regex.matches(in: data, range: range).compactMap { Range($0.range, in: data).map { String(data[$0]) } }
    }
}
