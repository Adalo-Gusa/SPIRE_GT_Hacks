import SwiftUI

/// One of the three family records reachable from the bookshelf.
enum RecordBook: String, CaseIterable, Identifiable, Hashable {
    case notebook
    case cookbook
    case storybook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notebook: "Family Notebook"
        case .cookbook: "Family Cookbook"
        case .storybook: "Create a Storybook"
        }
    }

    var blurb: String {
        switch self {
        case .notebook: "Stories and memories your family has recorded."
        case .cookbook: "Recipes passed down through the family."
        case .storybook: "Turn family memories into an illustrated storybook."
        }
    }

    var systemImage: String {
        switch self {
        case .notebook: "book.closed"
        case .cookbook: "fork.knife"
        case .storybook: "sparkles"
        }
    }

    var labelFill: Color {
        switch self {
        case .notebook: HeirloomColor.notebookPlum
        case .cookbook: HeirloomColor.rose
        case .storybook: HeirloomColor.polaroidFrame
        }
    }

    var labelText: Color {
        self == .storybook ? HeirloomColor.labelMuted : HeirloomColor.board
    }

    /// The book on the shelf that opens this record.
    var bookImage: String {
        switch self {
        case .notebook: "BookNotebook"
        case .cookbook: "BookCookbook"
        case .storybook: "BookStorybook"
        }
    }

    /// Frames from the Figma "records bookshelf" frame (435pt wide).
    var labelFrame: CGRect {
        switch self {
        case .notebook: CGRect(x: 142, y: 43, width: 238, height: 72)
        case .cookbook: CGRect(x: 22, y: 125, width: 243.9, height: 72)
        case .storybook: CGRect(x: 142, y: 207, width: 243.9, height: 72)
        }
    }

    var bookFrame: CGRect {
        switch self {
        case .notebook: CGRect(x: 146.11, y: 305, width: 189.98, height: 319.79)
        case .cookbook: CGRect(x: 66, y: 308.43, width: 82.4, height: 313.58)
        case .storybook: CGRect(x: 233.09, y: 359.69, width: 141.91, height: 264.66)
        }
    }
}

/// The Records tab: a bookshelf menu that pushes to each record's page.
struct RecordsView: View {
    @State private var path: [RecordBook] = []

    var body: some View {
        NavigationStack(path: $path) {
            RecordsBookshelfView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: RecordBook.self) { book in
                    RecordPageView(book: book)
                }
        }
        .tint(HeirloomColor.plum)
    }
}

/// The shelf of books with a label button for each. A book and its label open the same page.
struct RecordsBookshelfView: View {
    /// The slice of the Figma frame this screen shows, from just above the labels to below the shelf.
    private static let canvas = CGRect(x: 0, y: 30, width: 435, height: 700)
    /// Books drawn back to front, matching how they overlap in the design.
    private static let shelfOrder: [RecordBook] = [.notebook, .cookbook, .storybook]
    private static let labelOrder: [RecordBook] = [.notebook, .cookbook, .storybook]
    /// Where the shelf's legs end, measured from the top of the canvas.
    private static let shelfBottom: CGFloat = 690

    @Environment(\.tabBarTop) private var tabBarTop
    /// The book whose label or spine is being pressed; that book lifts off the shelf either way.
    @State private var pressedBook: RecordBook?

    var body: some View {
        GeometryReader { proxy in
            // This page runs under the tab bar (NavigationStack ignores the bar's inset), so fit the shelf
            // into the space above the yarn button rather than the whole page.
            let clearHeight = tabBarTop.map { $0 - proxy.frame(in: .global).minY - 8 } ?? proxy.size.height
            let scale = min(
                proxy.size.width / Self.canvas.width,
                max(clearHeight, 1) / Self.shelfBottom)

            ZStack(alignment: .topLeading) {
                Image("RecordsShelf")
                    .resizable()
                    .shadow(color: .black.opacity(0.25), radius: 5, x: 9, y: 8)
                    .place(in: CGRect(x: 11.1, y: 595.1, width: 429.3, height: 130.8))
                    .accessibilityHidden(true)

                ForEach(Self.shelfOrder) { book in
                    NavigationLink(value: book) {
                        Image(book.bookImage)
                            .resizable()
                            .offset(y: pressedBook == book ? -14 : 0)
                            .animation(.spring(duration: 0.25), value: pressedBook)
                    }
                    .buttonStyle(PressReportingStyle { pressed in setPressed(book, pressed) })
                    .place(in: book.bookFrame)
                    // The label buttons already expose these destinations to VoiceOver.
                    .accessibilityHidden(true)
                }

                ForEach(Self.labelOrder) { book in
                    NavigationLink(value: book) {
                        RecordLabel(book: book)
                            .scaleEffect(pressedBook == book ? 0.95 : 1)
                            .animation(.spring(duration: 0.25), value: pressedBook)
                    }
                    .buttonStyle(PressReportingStyle { pressed in setPressed(book, pressed) })
                    .place(in: book.labelFrame)
                }
            }
            .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
            .scaleEffect(scale, anchor: .top)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background { CorkboardBackground() }
    }

    private func setPressed(_ book: RecordBook, _ pressed: Bool) {
        if pressed {
            pressedBook = book
        } else if pressedBook == book {
            pressedBook = nil
        }
    }
}

private extension View {
    /// Positions a view at a frame given in Figma coordinates, relative to the bookshelf canvas.
    func place(in frame: CGRect) -> some View {
        self
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY - 30)
    }
}

/// The pill-shaped title button above the shelf.
private struct RecordLabel: View {
    let book: RecordBook

    var body: some View {
        Text(book.title)
            .font(.heirloomDisplay(fixedSize: 20))
            .foregroundStyle(book.labelText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Capsule()
                    .fill(book.labelFill)
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 5, y: 4)
                Capsule()
                    .strokeBorder(HeirloomColor.labelBorder, lineWidth: 3)
                    .padding(.horizontal, 7.3)
                    .padding(.vertical, 6)
            }
            .contentShape(Capsule())
    }
}

/// A button style with no look of its own that reports presses, so a book and its label can share one
/// pressed state: pressing either lifts the book and dips the label.
private struct PressReportingStyle: ButtonStyle {
    var onPressChange: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressChange(isPressed)
            }
    }
}

/// Placeholder for each record's page until those screens are designed.
struct RecordPageView: View {
    let book: RecordBook

    var body: some View {
        ZStack {
            CorkboardBackground()
            ContentUnavailableView {
                Label(book.title, systemImage: book.systemImage)
            } description: {
                Text(book.blurb)
            }
            .foregroundStyle(HeirloomColor.plum)
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    RecordsView()
}
