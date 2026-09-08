import SwiftUI

/// The totals screen: one card of numbers on the dark table, with the keypad and
/// the tip, split and rounding controls underneath.
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

                presetRow
                splitStepper
                roundModePicker

                Spacer(minLength: 8)

                keypad
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

    // MARK: - Tip

    /// One pill per preset. The selected one fills with Primary; a custom tip
    /// leaves them all empty.
    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(TipCalculator.tipPresets, id: \.self) { preset in
                let selected = model.isPresetSelected(preset)
                Button("\(preset)%") { model.selectPreset(preset) }
                    .buttonStyle(.plain)
                    .typography(Typography.body)
                    .foregroundStyle(selected ? Palette.onPrimary : Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(selected ? Palette.primary : Palette.surface, in: Capsule())
                    .accessibilityIdentifier("tip.preset.\(preset)")
            }
        }
        .animation(.snappy(duration: 0.18), value: model.selectedPreset)
    }

    // MARK: - Split

    private var splitStepper: some View {
        HStack {
            Text("Split")
                .typography(Typography.body)
                .foregroundStyle(Palette.textMuted)

            Spacer()

            stepperButton("minus", enabled: model.canDecrementSplit) { model.decrementSplit() }
                .accessibilityIdentifier("split.decrement")

            Text("\(model.splitCount)")
                .typography(Typography.amount)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: 44)
                .contentTransition(.numericText())
                .accessibilityIdentifier("split.count")

            stepperButton("plus", enabled: model.canIncrementSplit) { model.incrementSplit() }
                .accessibilityIdentifier("split.increment")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.snappy(duration: 0.16), value: model.splitCount)
    }

    private func stepperButton(
        _ symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Palette.primary : Palette.textMuted)
    }

    // MARK: - Rounding

    private var roundModePicker: some View {
        Picker("Rounding", selection: roundModeBinding) {
            ForEach(RoundMode.allCases, id: \.self) { mode in
                Text(roundModeLabel(mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("round.mode")
    }

    private var roundModeBinding: Binding<RoundMode> {
        Binding(get: { model.roundMode }, set: { model.roundMode = $0 })
    }

    private func roundModeLabel(_ mode: RoundMode) -> String {
        switch mode {
        case .off: return "Off"
        case .up: return "Round up"
        case .down: return "Round down"
        }
    }

    // MARK: - Keypad

    /// Four rows of three: the digits 1 through 9, then a blank, 0 and delete.
    private var keypad: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { digits in
                GridRow {
                    ForEach(digits, id: \.self) { digit in digitKey(digit) }
                }
            }
            GridRow {
                Color.clear.frame(height: KeyButtonStyle.minimumHeight)
                digitKey(0)
                Button { model.tapDelete() } label: {
                    Image(systemName: "delete.left")
                }
                .buttonStyle(.key(foreground: Palette.danger))
                .accessibilityLabel("Delete")
                .accessibilityIdentifier("keypad.delete")
            }
        }
    }

    private func digitKey(_ digit: Int) -> some View {
        Button("\(digit)") { model.tapDigit(digit) }
            .buttonStyle(.key)
            .accessibilityIdentifier("keypad.\(digit)")
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
