import Foundation

/// How the grand total is rounded to a whole currency unit.
enum RoundMode {
    case off
    case up
    case down
}

/// The calculation engine. All money is whole cents (`Int`), never `Double`.
///
/// Declarations only — no behaviour yet. TIP-1's failing test needs these
/// symbols to exist so it fails on wrong values instead of on a missing type.
final class TipCalculator {

    // Inputs
    var bill: Int = 0
    var tipPercent: Int = 20
    var splitCount: Int = 1
    var roundMode: RoundMode = .off

    // Outputs
    var tipTotal: Int { 0 }
    var grandTotal: Int { 0 }
    var perPerson: Int { 0 }
    var perPersonTip: Int { 0 }

    /// How many people pay one cent more than `perPerson`.
    var remainderCount: Int { 0 }

    /// How many people pay one cent more than `perPersonTip`.
    var tipRemainderCount: Int { 0 }

    /// `percent` of `bill` cents, rounded half up on the final cent.
    static func roundHalfUp(bill: Int, percent: Int) -> Int { 0 }
}
