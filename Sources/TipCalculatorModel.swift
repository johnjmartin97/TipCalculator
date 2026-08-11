import Foundation

/// How the grand total is rounded to a whole currency unit.
enum RoundMode {
    case off
    case up
    case down
}

/// The calculation engine. All money is whole cents (`Int`), never `Double`.
final class TipCalculator {

    // Inputs
    var billCents: Int = 0
    var tipPercent: Int = 20
    var splitCount: Int = 1
    var roundMode: RoundMode = .off

    /// The preset the tip currently comes from, or `nil` when the tip is custom.
    ///
    /// Declarations only from here down — no behaviour yet. TIP-3's failing
    /// test needs these symbols to exist so it fails on wrong behaviour instead
    /// of on a missing member.
    var selectedPreset: Int?

    /// True when the tip was typed rather than picked from a preset.
    var isCustomTip: Bool = false

    /// The tip percentages offered as one-tap buttons.
    static let tipPresets: [Int] = [15, 18, 20, 25]

    /// The bill holds at most this many digits.
    static let maximumBillDigits = 9

    /// The split may not go below this, nor above `maximumSplitCount`.
    static let minimumSplitCount = 1
    static let maximumSplitCount = 50

    // Input actions

    /// Shifts one digit in from the right of the bill.
    func tapDigit(_ digit: Int) {}

    /// Shifts the rightmost digit off the bill.
    func tapDelete() {}

    func selectPreset(_ percent: Int) {}

    func setCustomTip(_ percent: Int) {}

    func isPresetSelected(_ percent: Int) -> Bool { false }

    func incrementSplit() {}

    func decrementSplit() {}

    var canIncrementSplit: Bool { false }

    var canDecrementSplit: Bool { false }

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
