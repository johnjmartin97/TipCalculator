import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Every colour in the app, defined once. Each token carries both appearance
/// values so light and dark live next to each other and can be asserted in tests.
/// View code uses `Palette.primary` and never a hex literal.
struct ColorToken: Equatable {
    let lightHex: UInt32
    let darkHex: UInt32

    func hex(for scheme: ColorScheme) -> UInt32 {
        scheme == .dark ? darkHex : lightHex
    }

    var color: Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgbHex: darkHex)
                : UIColor(rgbHex: lightHex)
        })
        #else
        return Color(rgbHex: lightHex)
        #endif
    }
}

enum Palette {
    /// The raw tokens, for tests and for anything that needs both appearances.
    enum Tokens {
        static let background     = ColorToken(lightHex: 0xF2F5F3, darkHex: 0x0B1311)
        static let surface        = ColorToken(lightHex: 0xFFFFFF, darkHex: 0x18221F)
        static let surfaceRaised  = ColorToken(lightHex: 0xE8EDEA, darkHex: 0x22302C)
        static let primary        = ColorToken(lightHex: 0x067A58, darkHex: 0x35D6A4)
        static let onPrimary      = ColorToken(lightHex: 0xFFFFFF, darkHex: 0x052018)
        static let secondary      = ColorToken(lightHex: 0x0F4C46, darkHex: 0x7FC9B4)
        static let accent         = ColorToken(lightHex: 0xE08A18, darkHex: 0xF5B14A)
        static let success        = ColorToken(lightHex: 0x067A58, darkHex: 0x35D6A4)
        static let danger         = ColorToken(lightHex: 0xB3372C, darkHex: 0xFF7A6B)
        static let textPrimary    = ColorToken(lightHex: 0x10201C, darkHex: 0xF2F7F5)
        static let textMuted      = ColorToken(lightHex: 0x5B6B66, darkHex: 0x93A5A0)
        static let separator      = ColorToken(lightHex: 0xDDE4E1, darkHex: 0x2B3835)

        static let all: [ColorToken] = [
            background, surface, surfaceRaised, primary, onPrimary, secondary,
            accent, success, danger, textPrimary, textMuted, separator
        ]
    }

    /// Screen behind everything.
    static let background    = Tokens.background.color
    /// Totals card, keypad keys, history rows, sheets.
    static let surface       = Tokens.surface.color
    /// Pressed key, selected segment track.
    static let surfaceRaised = Tokens.surfaceRaised.color
    /// Selected tip preset, save button, grand total.
    static let primary       = Tokens.primary.color
    /// Text sitting on a filled primary shape.
    static let onPrimary     = Tokens.onPrimary.color
    /// Per-person label, section headings.
    static let secondary     = Tokens.secondary.color
    /// The percent mark in the icon, the remainder line.
    static let accent        = Tokens.accent.color
    /// Save confirmation.
    static let success       = Tokens.success.color
    /// Delete, clear-all confirmation.
    static let danger        = Tokens.danger.color
    /// Amounts, key digits, row titles.
    static let textPrimary   = Tokens.textPrimary.color
    /// Captions, disabled keys, timestamps.
    static let textMuted     = Tokens.textMuted.color
    /// Hairlines, card outlines.
    static let separator     = Tokens.separator.color

    /// The single shadow in the app: the totals card. None in dark.
    enum CardShadow {
        static let radius: CGFloat = 12
        static let yOffset: CGFloat = 2
        static let lightOpacity: Double = 0.06

        static func color(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .clear : Color.black.opacity(lightOpacity)
        }
    }
}

// MARK: - Hex

#if canImport(UIKit)
extension UIColor {
    convenience init(rgbHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

extension Color {
    init(rgbHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
