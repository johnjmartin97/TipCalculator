import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The six type roles. Numbers are SF Rounded with monospaced digits so they do
/// not jitter while they roll; labels are SF Pro Text. Every role scales with
/// Dynamic Type from its matching text style.
enum Typography {
    struct Role {
        let size: CGFloat
        let weight: Font.Weight
        let design: Font.Design
        let textStyle: Font.TextStyle
        let monospacedDigits: Bool

        /// The font at a given Dynamic Type size.
        func font(at typeSize: DynamicTypeSize) -> Font {
            let scaled = Role.scaledSize(size, textStyle: textStyle, typeSize: typeSize)
            let font = Font.system(size: scaled, weight: weight, design: design)
            return monospacedDigits ? font.monospacedDigit() : font
        }

        /// The font at the device's current Dynamic Type size.
        var font: Font { font(at: .large) }

        static func scaledSize(
            _ size: CGFloat,
            textStyle: Font.TextStyle,
            typeSize: DynamicTypeSize
        ) -> CGFloat {
            #if canImport(UIKit)
            let metrics = UIFontMetrics(forTextStyle: textStyle.uiTextStyle)
            let traits = UITraitCollection(preferredContentSizeCategory: typeSize.contentSizeCategory)
            return metrics.scaledValue(for: size, compatibleWith: traits)
            #else
            return size
            #endif
        }
    }

    /// Grand total.
    static let display = Role(size: 56, weight: .bold, design: .rounded,
                              textStyle: .largeTitle, monospacedDigits: true)
    /// Per-person amount.
    static let title = Role(size: 30, weight: .semibold, design: .rounded,
                            textStyle: .title, monospacedDigits: true)
    /// Bill, tip total, history amounts.
    static let amount = Role(size: 22, weight: .medium, design: .rounded,
                             textStyle: .title3, monospacedDigits: true)
    /// Keypad digits.
    static let key = Role(size: 26, weight: .medium, design: .rounded,
                          textStyle: .title2, monospacedDigits: true)
    /// Labels, presets, buttons.
    static let body = Role(size: 17, weight: .regular, design: .default,
                           textStyle: .body, monospacedDigits: false)
    /// Remainder line, timestamps, hints.
    static let caption = Role(size: 13, weight: .medium, design: .default,
                              textStyle: .caption, monospacedDigits: false)

    /// The display total shrinks rather than wrapping or truncating.
    static let displayMinimumScaleFactor: CGFloat = 0.6
}

// MARK: - Applying a role

private struct TypographyModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let role: Typography.Role

    func body(content: Content) -> some View {
        content.font(role.font(at: typeSize))
    }
}

extension View {
    /// Applies a type role, scaled to the reader's Dynamic Type setting.
    func typography(_ role: Typography.Role) -> some View {
        modifier(TypographyModifier(role: role))
    }
}

// MARK: - Bridging to UIKit metrics

#if canImport(UIKit)
extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}

extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}
#endif
