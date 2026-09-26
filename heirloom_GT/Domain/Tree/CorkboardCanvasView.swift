import SwiftUI

/// A conspiracy-theory / evidence corkboard SwiftUI canvas that automatically
/// orients family members with pictures, names underneath, pushpins, and sagging red strings.
public struct CorkboardCanvasView: View {
    public let state: CorkboardLayoutState
    public var onSelectMember: ((MemberDocument) -> Void)?
    public var onRefresh: (() -> Void)?

    @State private var zoomScale: CGFloat = 1.0
    @State private var selectedMemberId: String? = nil

    public init(
        state: CorkboardLayoutState,
        onSelectMember: ((MemberDocument) -> Void)? = nil,
        onRefresh: (() -> Void)? = nil
    ) {
        self.state = state
        self.onSelectMember = onSelectMember
        self.onRefresh = onRefresh
    }

    public var body: some View {
        ZStack {
            // Corkboard Background
            corkboardBackground

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // 1. Generation Tier Divider Guides
                    generationGuidelines

                    // 2. Connecting Red Twine Strings (rendered under photo cards)
                    ForEach(state.strings) { stringLine in
                        CorkboardStringView(stringLine: stringLine)
                    }

                    // 3. Evidence Polaroid Cards with Pushpins
                    ForEach(state.nodes) { node in
                        CorkboardCardView(
                            node: node,
                            isSelected: selectedMemberId == node.id
                        ) {
                            selectedMemberId = node.id
                            onSelectMember?(node.member)
                        }
                        .position(x: node.x + (node.size.width / 2.0), y: node.y + (node.size.height / 2.0))
                    }
                }
                .frame(width: max(state.canvasSize.width, 1300), height: max(state.canvasSize.height, 950))
            }
        }
    }

    // MARK: - Subviews

    private var corkboardBackground: some View {
        ZStack {
            Color(red: 0.83, green: 0.70, blue: 0.54)
                .ignoresSafeArea()
            // Subtle corkboard noise/grid overlay
            Rectangle()
                .strokeBorder(Color(red: 0.55, green: 0.40, blue: 0.28).opacity(0.15), lineWidth: 1)
        }
    }

    private var generationGuidelines: some View {
        VStack(alignment: .leading, spacing: 260) {
            Group {
                Text("GENERATION 1 · FOREBEARS & ELDERS")
                Text("GENERATION 2 · PARENTS & SIBLINGS")
                Text("GENERATION 3 · NEXT GENERATION")
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(Color(red: 0.45, green: 0.32, blue: 0.20).opacity(0.5))
            .padding(.leading, 24)
        }
        .padding(.top, 40)
    }
}

// MARK: - Evidence String View (Curved Red Twine)

struct CorkboardStringView: View {
    let stringLine: CorkboardString

    var body: some View {
        Path { path in
            path.move(to: stringLine.fromPoint)
            let midX = (stringLine.fromPoint.x + stringLine.toPoint.x) / 2.0
            let midY = (stringLine.fromPoint.y + stringLine.toPoint.y) / 2.0 + stringLine.sagAmount
            let controlPoint = CGPoint(x: midX, y: midY)
            path.addQuadCurve(to: stringLine.toPoint, control: controlPoint)
        }
        .stroke(
            Color(hex: stringLine.colorHex),
            style: StrokeStyle(lineWidth: stringLine.type == .spouse ? 2.8 : 2.2, lineCap: .round, lineJoin: .round)
        )
        // Natural cast shadow onto corkboard
        .shadow(color: Color.black.opacity(0.35), radius: 2.5, x: 1.5, y: 3.0)
    }
}

// MARK: - Polaroid Card View

struct CorkboardCardView: View {
    let node: CorkboardNode
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // Polaroid Frame
            VStack(spacing: 6) {
                // Photo Area
                ZStack {
                    if let urlStr = node.member.avatarUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                initialsPlaceholder
                            }
                        }
                    } else {
                        initialsPlaceholder
                    }
                }
                .frame(width: node.size.width - 20, height: 110)
                .background(Color(white: 0.90))
                .clipped()
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                )

                // Space for Name Right Underneath
                VStack(spacing: 2) {
                    Text(node.name)
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundColor(Color(white: 0.15))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if node.member.birthYear > 0 {
                        Text("b. \(String(node.member.birthYear)) · Gen \(node.member.generationTier)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.gray)
                    } else {
                        Text("Gen \(node.member.generationTier)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.gray)
                    }
                }
                .frame(height: 38)
            }
            .padding(.top, 14)
            .padding(.bottom, 8)
            .padding(.horizontal, 10)
            .frame(width: node.size.width, height: node.size.height)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.98))
                    .shadow(color: isSelected ? Color.red.opacity(0.5) : Color.black.opacity(0.24), radius: isSelected ? 8 : 5, x: 2, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? Color.red : Color.black.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
            .rotationEffect(.degrees(node.rotationDegrees))
            .onTapGesture {
                onTap()
            }

            // Top Pushpin (Evidence pinhead)
            pushpinView
                .offset(y: -4)
        }
    }

    private var initialsPlaceholder: some View {
        ZStack {
            Color(red: 0.92, green: 0.88, blue: 0.82)
            Text(initials(of: node.name))
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundColor(Color(red: 0.45, green: 0.35, blue: 0.25))
        }
    }

    private var pushpinView: some View {
        ZStack {
            // Pinhead drop shadow
            Circle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 14, height: 14)
                .offset(x: 1.5, y: 2.5)

            // Pinhead body
            Circle()
                .fill(Color(hex: node.pinColorHex))
                .frame(width: 14, height: 14)

            // Specular reflection highlight
            Circle()
                .fill(Color.white.opacity(0.65))
                .frame(width: 5, height: 5)
                .offset(x: -2.5, y: -2.5)
        }
    }

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ").map { String($0.prefix(1)) }
        return parts.prefix(2).joined()
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hexClean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexClean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexClean.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 214, 48, 49) // Default red string
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
