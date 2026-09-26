import SwiftUI
import CoreText

/// Palette pulled from the HeirLoom Figma file.
enum HeirloomColor {
    static let board = Color(hex: 0xD1B597)
    static let gridLine = Color(hex: 0xEED8C1).opacity(0.35)

    static let plum = Color(hex: 0x4B3045)
    static let plumMuted = Color(hex: 0x64465D)
    static let tabLabel = Color(hex: 0x77536F)

    static let rose = Color(hex: 0xCB4770)
    static let roseLight = Color(hex: 0xE76D94)

    static let string = Color(hex: 0xBE5353)

    static let polaroidFrame = Color(hex: 0xE3CEB8)
    static let polaroidPhoto = Color(hex: 0xF0E4D7)

    static let notebookPlum = Color(hex: 0x55324D)
    static let labelBorder = Color(hex: 0xB59878)
    static let labelMuted = Color(hex: 0x897865)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Typography

enum HeirloomFont {
    /// PostScript name of the display face used in the Figma file.
    static let displayName = "MomoTrustDisplay-Regular"

    /// Registers any .ttf/.otf bundled with the app so fonts work without Info.plist `UIAppFonts` entries.
    static func registerBundledFonts() {
        let urls = ["ttf", "otf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static var isDisplayAvailable: Bool {
        UIFont(name: displayName, size: 12) != nil
    }
}

extension Font {
    /// The HeirLoom display face, scaling with Dynamic Type. Falls back to rounded system type if the font isn't bundled.
    static func heirloomDisplay(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        if HeirloomFont.isDisplayAvailable {
            return .custom(HeirloomFont.displayName, size: size, relativeTo: style)
        }
        let scaledSize = UIFontMetrics(forTextStyle: style.uiTextStyle).scaledValue(for: size)
        return .system(size: scaledSize, weight: .heavy, design: .rounded)
    }

    /// Fixed-size display face for artwork (like the logo) that must not reflow with Dynamic Type.
    static func heirloomDisplay(fixedSize size: CGFloat) -> Font {
        if HeirloomFont.isDisplayAvailable {
            return .custom(HeirloomFont.displayName, fixedSize: size)
        }
        return .system(size: size, weight: .heavy, design: .rounded)
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
