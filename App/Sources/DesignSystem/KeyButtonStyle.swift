import SwiftUI

/// A keypad key: a 16 pt continuous rounded rectangle in Surface that fills with
/// Surface raised and scales to 0.96 while held, so pressing feels physical.
/// Written as a style rather than an image so it follows appearance and animates.
struct KeyButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Corner radius for a key, from the layout scale.
    static let cornerRadius: CGFloat = 16
    /// Keys are never shorter than this, and never smaller than a 44 pt target.
    static let minimumHeight: CGFloat = 56
    static let minimumTapTarget: CGFloat = 44
    static let pressedScale: CGFloat = 0.96

    /// Tint of the label. Delete and other non-digit keys pass their own.
    var foreground: Color = Palette.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typography(Typography.key)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Self.minimumHeight)
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? Palette.surfaceRaised : Palette.surface)
            )
            .scaleEffect(configuration.isPressed ? Self.pressedScale : 1.0)
            .accessibilityAddTraits(.isButton)
            .animation(pressAnimation(isPressed: configuration.isPressed),
                       value: configuration.isPressed)
    }

    /// Press down is a quick ease out; release springs back. With Reduce Motion
    /// on, both collapse to a plain crossfade.
    private func pressAnimation(isPressed: Bool) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.1)
        }
        return isPressed
            ? .easeOut(duration: 0.09)
            : .spring(response: 0.14, dampingFraction: 0.8)
    }
}

extension ButtonStyle where Self == KeyButtonStyle {
    /// `.buttonStyle(.key)` for a keypad digit.
    static var key: KeyButtonStyle { KeyButtonStyle() }

    /// A key with a different label colour, such as delete in Danger.
    static func key(foreground: Color) -> KeyButtonStyle {
        KeyButtonStyle(foreground: foreground)
    }
}

#Preview {
    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
        ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
            GridRow {
                ForEach(row, id: \.self) { digit in
                    Button(digit) {}.buttonStyle(.key)
                }
            }
        }
    }
    .padding(20)
    .background(Palette.background)
}
