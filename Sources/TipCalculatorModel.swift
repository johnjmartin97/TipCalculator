import Foundation
import Observation

/// How the grand total is rounded to a whole currency unit.
enum RoundMode: CaseIterable {
    case off
    case up
    case down
}

/// The calculation engine. All money is whole cents (`Int`), never `Double`.
/// Observable so the screen redraws the moment an input changes.
@Observable
final class TipCalculator {

    // Inputs
    var billCents: Int = 0
    var tipPercent: Int = 20
    var splitCount: Int = 1
    var roundMode: RoundMode = .off

    /// The preset the tip currently comes from, or `nil` when the tip is custom.
    var selectedPreset: Int? = 20

    /// True when the tip was typed rather than picked from a preset.
    var isCustomTip: Bool = false

    /// The tip percentages offered as one-tap buttons.
    static let tipPresets: [Int] = [15, 18, 20, 25]

    /// The bill holds at most this many digits.
    static let maximumBillDigits = 9

    /// One past the largest bill, so `$9,999,999.99` is the ceiling.
    static let billLimit = 1_000_000_000

    /// The split may not go below this, nor above `maximumSplitCount`.
    static let minimumSplitCount = 1
    static let maximumSplitCount = 50

    // Input actions

    /// Shifts one digit in from the right of the bill. Taps past the digit limit
    /// are ignored; a leading zero never lands, so the bill stays empty.
    func tapDigit(_ digit: Int) {
        guard billCents < TipCalculator.billLimit / 10 else { return }
        billCents = billCents * 10 + digit
    }

    /// Shifts the rightmost digit off the bill.
    func tapDelete() {
        billCents /= 10
    }

    /// Picks a preset tip. The custom tip is dropped.
    func selectPreset(_ percent: Int) {
        tipPercent = percent
        selectedPreset = percent
        isCustomTip = false
    }

    /// Types a tip percent. Clamps to 0...100 and deselects every preset, even
    /// when the value happens to equal one.
    func setCustomTip(_ percent: Int) {
        tipPercent = min(max(percent, 0), 100)
        selectedPreset = nil
        isCustomTip = true
    }

    func isPresetSelected(_ percent: Int) -> Bool {
        selectedPreset == percent
    }

    func incrementSplit() {
        guard canIncrementSplit else { return }
        splitCount += 1
    }

    func decrementSplit() {
        guard canDecrementSplit else { return }
        splitCount -= 1
    }

    var canIncrementSplit: Bool { splitCount < TipCalculator.maximumSplitCount }

    var canDecrementSplit: Bool { splitCount > TipCalculator.minimumSplitCount }

    // Outputs

    /// What the grand total rounds to, before the tip is worked back out.
    /// Rounding moves the total, and the tip absorbs the difference.
    var grandTotal: Int {
        let unrounded = billCents + TipCalculator.roundHalfUp(bill: billCents, percent: tipPercent)
        switch roundMode {
        case .off:
            return unrounded
        case .up:
            return (unrounded + 99) / 100 * 100
        case .down:
            // Rounding down must never take the tip below zero.
            return max(unrounded / 100 * 100, billCents)
        }
    }

    var tipTotal: Int { grandTotal - billCents }

    var perPerson: Int { grandTotal / splitCount }
    var perPersonTip: Int { tipTotal / splitCount }

    /// How many people pay one cent more than `perPerson`.
    var remainderCount: Int { grandTotal % splitCount }

    /// How many people pay one cent more than `perPersonTip`.
    var tipRemainderCount: Int { tipTotal % splitCount }

    /// `percent` of `bill` cents, rounded half up on the final cent.
    static func roundHalfUp(bill: Int, percent: Int) -> Int {
        (bill * percent + 50) / 100
    }
}
