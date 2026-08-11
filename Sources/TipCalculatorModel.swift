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
    var bill: Int = 0
    var tipPercent: Int = 20
    var splitCount: Int = 1
    var roundMode: RoundMode = .off

    // Outputs

    /// What the grand total rounds to, before the tip is worked back out.
    /// Rounding moves the total, and the tip absorbs the difference.
    var grandTotal: Int {
        let unrounded = bill + TipCalculator.roundHalfUp(bill: bill, percent: tipPercent)
        switch roundMode {
        case .off:
            return unrounded
        case .up:
            return (unrounded + 99) / 100 * 100
        case .down:
            // Rounding down must never take the tip below zero.
            return max(unrounded / 100 * 100, bill)
        }
    }

    var tipTotal: Int { grandTotal - bill }

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
