import SwiftUI

/// One of the family records reachable from the bookshelf.
enum RecordBook: String, CaseIterable, Identifiable, Hashable {
    case notebook
    case cookbook
    case storybook
    case photoAlbum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notebook: "Family Notebook"
        case .cookbook: "Family Cookbook"
        case .storybook: "Create a Storybook"
        case .photoAlbum: "Photo Album"
        }
    }

    var blurb: String {
        switch self {
        case .notebook: "Stories and memories your family has recorded."
        case .cookbook: "Recipes passed down through the family."
        case .storybook: "Turn family memories into an illustrated storybook."
        case .photoAlbum: "Photos your family has pinned to the board."
        }
    }

    var systemImage: String {
        switch self {
        case .notebook: "book.closed"
        case .cookbook: "fork.knife"
        case .storybook: "sparkles"
        case .photoAlbum: "photo.on.rectangle"
        }
    }

    var labelFill: Color {
        switch self {
        case .notebook: HeirloomColor.notebookPlum
        case .cookbook: HeirloomColor.rose
        case .storybook: HeirloomColor.polaroidFrame
        case .photoAlbum: HeirloomColor.albumBrown
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
        case .photoAlbum: "BookPhotoAlbum"
        }
    }

    /// Frames from the Figma "records bookshelf" frame (435pt wide).
    var labelFrame: CGRect {
        switch self {
        case .cookbook: CGRect(x: 100, y: 439, width: 243.9, height: 63)
        case .notebook: CGRect(x: 100, y: 515, width: 243.9, height: 63)
        case .storybook: CGRect(x: 100, y: 591, width: 243.9, height: 63)
        case .photoAlbum: CGRect(x: 100, y: 667, width: 243.9, height: 63)
        }
    }

    var bookFrame: CGRect {
        switch self {
        case .notebook: CGRect(x: 119, y: 34, width: 176, height: 319.79)
        case .cookbook: CGRect(x: 50, y: 72, width: 75, height: 281.58)
        case .storybook: CGRect(x: 199, y: 89, width: 141.91, height: 264.66)
        case .photoAlbum: CGRect(x: 341, y: 40, width: 46, height: 313.58)
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
                    switch book {
                    case .notebook: FamilyNotebookView()
                    default: RecordPageView(book: book)
                    }
                }
        }
        .tint(HeirloomColor.plum)
    }
}

/// The shelf of books with a label button for each. A book and its label open the same page.
struct RecordsBookshelfView: View {
    /// The slice of the Figma frame this screen shows, from just above the books to below the last label.
    static let canvas = CGRect(x: 0, y: 24, width: 435, height: 716)
    /// Books drawn back to front, matching how they overlap in the design.
    private static let shelfOrder: [RecordBook] = [.notebook, .photoAlbum, .cookbook, .storybook]
    private static let labelOrder: [RecordBook] = [.cookbook, .notebook, .storybook, .photoAlbum]
    /// Where the lowest label (and its shadow) ends, measured from the top of the canvas.
    private static let contentBottom: CGFloat = 712

    @Environment(\.tabBarTop) private var tabBarTop
    /// The book whose label or spine is being pressed; that book lifts off the shelf either way.
    @State private var pressedBook: RecordBook?

    var body: some View {
        GeometryReader { proxy in
            // This page runs under the tab bar (NavigationStack ignores the bar's inset), so fit the shelf and
            // labels into the space above the yarn button rather than the whole page.
            let clearHeight = tabBarTop.map { $0 - proxy.frame(in: .global).minY - 8 } ?? proxy.size.height
            let scale = min(
                proxy.size.width / Self.canvas.width,
                max(clearHeight, 1) / Self.contentBottom)

            ZStack(alignment: .topLeading) {
                Image("RecordsShelf")
                    .resizable()
                    .shadow(color: .black.opacity(0.25), radius: 5, x: 9, y: 8)
                    .place(in: CGRect(x: 11.1, y: 327.1, width: 429.3, height: 130.8))
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
            .position(x: frame.midX, y: frame.midY - RecordsBookshelfView.canvas.minY)
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
                GeometryReader { proxy in
                    Capsule()
                        .strokeBorder(HeirloomColor.labelBorder, lineWidth: 3)
                        .padding(.horizontal, 7.3)
                        .padding(.vertical, proxy.size.height * 0.083)
                }
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
        .environmentObject(FamilyArchive())
}
