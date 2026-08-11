import SwiftUI

/// The totals screen: one card of numbers on the dark table. Read-only for now —
/// the keypad and the controls arrive with the input ticket.
struct RootView: View {
    let model: TipCalculator

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let display = DisplayState(model: model, locale: locale)

        return ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Tip")
                    .typography(Typography.body)
                    .foregroundStyle(Palette.secondary)
                    .accessibilityIdentifier("app.title")

                totalsCard(display)

                Spacer()
            }
            .padding(20)
        }
    }

    private func totalsCard(_ display: DisplayState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Bill", display.billText)
            row("Tip", display.tipText)

            Text(display.totalText)
                .typography(Typography.display)
                .minimumScaleFactor(Typography.displayMinimumScaleFactor)
                .lineLimit(1)
                .foregroundStyle(Palette.primary)
                .accessibilityIdentifier("total.amount")

            Text(display.perPersonText)
                .typography(Typography.title)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityIdentifier("perPerson.amount")

            if let remainder = display.remainderText {
                Text(remainder)
                    .typography(Typography.caption)
                    .foregroundStyle(Palette.accent)
                    .accessibilityIdentifier("remainder.line")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .shadow(
            color: Palette.CardShadow.color(for: scheme),
            radius: Palette.CardShadow.radius,
            y: Palette.CardShadow.yOffset
        )
    }

    private func row(_ label: String, _ amount: String) -> some View {
        HStack {
            Text(label)
                .typography(Typography.body)
                .foregroundStyle(Palette.textMuted)
            Spacer()
            Text(amount)
                .typography(Typography.amount)
                .foregroundStyle(Palette.textPrimary)
        }
    }
}

#Preview { RootView(model: TipCalculator()) }
