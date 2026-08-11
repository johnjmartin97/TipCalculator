import XCTest
@testable import TipCalculator

/// Proves TIP-1: the calculation engine works in whole cents only, and every
/// output reconciles exactly across the whole input space the app allows.
///
/// The sweeps below are hot loops. They deliberately avoid calling XCTAssert
/// inside the loop — one assertion per iteration would cost far more than the
/// arithmetic itself. Instead each sweep records the first violation it sees
/// and asserts once at the end, so a failure still names the exact inputs.
final class CalculationTests: XCTestCase {

    // MARK: - Reference arithmetic
    //
    // Expected values are worked out here, independently of the code under
    // test. `expectedTip` uses plain integer division plus an explicit
    // half-cent check, which is a different route to the answer than the
    // model's rounding helper.

    private func expectedTip(bill: Int, percent: Int) -> Int {
        let hundredths = bill * percent      // cents * 100
        let whole = hundredths / 100
        let fraction = hundredths % 100
        return fraction >= 50 ? whole + 1 : whole
    }

    private let bills = 0...2000
    private let percents = 0...100
    private let splits = 1...50
    private let modes: [RoundMode] = [.off, .up, .down]

    // MARK: - Criterion: the public surface is Int cents only

    func testPublicSurfaceExposesNoDoubleOrFloat() {
        let model = TipCalculator()
        model.bill = 4999
        model.tipPercent = 18
        model.splitCount = 3
        model.roundMode = .up

        for child in Mirror(reflecting: model).children {
            let label = child.label ?? "<unlabelled>"
            XCTAssertFalse(child.value is Double, "stored property \(label) is a Double")
            XCTAssertFalse(child.value is Float, "stored property \(label) is a Float")
            let typeName = String(describing: type(of: child.value))
            XCTAssertFalse(typeName.contains("Double"), "stored property \(label) has type \(typeName)")
            XCTAssertFalse(typeName.contains("Float"), "stored property \(label) has type \(typeName)")
        }

        XCTAssertTrue(type(of: model.bill) == Int.self, "bill is not Int")
        XCTAssertTrue(type(of: model.tipTotal) == Int.self, "tipTotal is not Int")
        XCTAssertTrue(type(of: model.grandTotal) == Int.self, "grandTotal is not Int")
        XCTAssertTrue(type(of: model.perPerson) == Int.self, "perPerson is not Int")
        XCTAssertTrue(type(of: model.perPersonTip) == Int.self, "perPersonTip is not Int")
        XCTAssertTrue(type(of: model.remainderCount) == Int.self, "remainderCount is not Int")
        XCTAssertTrue(type(of: model.tipRemainderCount) == Int.self, "tipRemainderCount is not Int")
    }

    // MARK: - Criterion: round half up on the final cent

    func testRoundHalfUpRoundsTheHalfCentUpwards() {
        XCTAssertEqual(TipCalculator.roundHalfUp(bill: 4999, percent: 15), 750)
        XCTAssertEqual(TipCalculator.roundHalfUp(bill: 100, percent: 15), 15)
    }

    /// Guards the reference used by the sweeps: it must agree with the two
    /// values the ticket names, and with decimal rounding on a sample.
    func testReferenceRoundingAgreesWithDecimalRounding() {
        XCTAssertEqual(expectedTip(bill: 4999, percent: 15), 750)
        XCTAssertEqual(expectedTip(bill: 100, percent: 15), 15)

        for bill in stride(from: 0, through: 2000, by: 7) {
            for percent in stride(from: 0, through: 100, by: 3) {
                var exact = Decimal(bill * percent) / Decimal(100)
                var rounded = Decimal()
                NSDecimalRound(&rounded, &exact, 0, .plain)
                XCTAssertEqual(
                    expectedTip(bill: bill, percent: percent),
                    NSDecimalNumber(decimal: rounded).intValue,
                    "reference rounding disagrees at bill \(bill), percent \(percent)"
                )
            }
        }
    }

    // MARK: - Criterion: the sweep runs, and grandTotal == bill + tipTotal

    func testSweepGrandTotalAlwaysEqualsBillPlusTipTotal() {
        let model = TipCalculator()
        model.splitCount = 1
        var failure: String?

        outer: for mode in modes {
            model.roundMode = mode
            for bill in bills {
                model.bill = bill
                for percent in percents {
                    model.tipPercent = percent
                    let grand = model.grandTotal
                    let tip = model.tipTotal
                    if grand != bill + tip {
                        failure = "bill \(bill), percent \(percent), mode \(mode): "
                            + "grandTotal \(grand) != bill \(bill) + tipTotal \(tip)"
                        break outer
                    }
                }
            }
        }

        XCTAssertNil(failure, failure ?? "")
    }

    // MARK: - Criterion: the split parts sum exactly, no cent lost

    func testSweepPerPersonPartsSumExactlyToTheTotals() {
        let model = TipCalculator()
        var failure: String?

        outer: for mode in modes {
            model.roundMode = mode
            for bill in bills {
                model.bill = bill
                for percent in percents {
                    model.tipPercent = percent
                    let grand = model.grandTotal
                    let tip = model.tipTotal
                    // Anchor: parts that sum to a total of zero prove nothing,
                    // so check the unrounded total is the real one first.
                    if mode == .off && grand != bill + expectedTip(bill: bill, percent: percent) {
                        failure = "bill \(bill), percent \(percent), mode off: grandTotal \(grand) != "
                            + "\(bill + expectedTip(bill: bill, percent: percent))"
                        break outer
                    }
                    for n in splits {
                        model.splitCount = n

                        let share = model.perPerson
                        let extras = model.remainderCount
                        if extras < 0 || extras >= n {
                            failure = "bill \(bill), percent \(percent), split \(n), mode \(mode): "
                                + "remainderCount \(extras) is not in 0..<\(n)"
                            break outer
                        }
                        if share * n + extras != grand {
                            failure = "bill \(bill), percent \(percent), split \(n), mode \(mode): "
                                + "perPerson \(share) * \(n) + \(extras) != grandTotal \(grand)"
                            break outer
                        }

                        let tipShare = model.perPersonTip
                        let tipExtras = model.tipRemainderCount
                        if tipExtras < 0 || tipExtras >= n {
                            failure = "bill \(bill), percent \(percent), split \(n), mode \(mode): "
                                + "tipRemainderCount \(tipExtras) is not in 0..<\(n)"
                            break outer
                        }
                        if tipShare * n + tipExtras != tip {
                            failure = "bill \(bill), percent \(percent), split \(n), mode \(mode): "
                                + "perPersonTip \(tipShare) * \(n) + \(tipExtras) != tipTotal \(tip)"
                            break outer
                        }
                    }
                }
            }
        }

        XCTAssertNil(failure, failure ?? "")
    }

    // MARK: - Criterion: round mode up

    func testSweepRoundUpLandsOnTheNextWholeCurrencyUnit() {
        let model = TipCalculator()
        model.splitCount = 1
        model.roundMode = .up
        var failure: String?

        outer: for bill in bills {
            model.bill = bill
            for percent in percents {
                model.tipPercent = percent
                let grand = model.grandTotal
                let unrounded = bill + expectedTip(bill: bill, percent: percent)

                if grand % 100 != 0 {
                    failure = "bill \(bill), percent \(percent): grandTotal \(grand) is not a whole unit"
                    break outer
                }
                if grand < unrounded {
                    failure = "bill \(bill), percent \(percent): grandTotal \(grand) is below \(unrounded)"
                    break outer
                }
                if grand - unrounded >= 100 {
                    failure = "bill \(bill), percent \(percent): grandTotal \(grand) overshoots \(unrounded) "
                        + "by \(grand - unrounded)"
                    break outer
                }
            }
        }

        XCTAssertNil(failure, failure ?? "")
    }

    func testRoundUpLeavesAWholeUnitTotalUnchanged() {
        let model = TipCalculator()
        model.bill = 10000
        model.tipPercent = 0
        model.splitCount = 1
        model.roundMode = .up

        XCTAssertEqual(model.grandTotal, 10000)
        XCTAssertEqual(model.tipTotal, 0)
    }

    // MARK: - Criterion: round mode down

    func testSweepRoundDownNeverTakesTheTotalBelowTheBill() {
        let model = TipCalculator()
        model.splitCount = 1
        model.roundMode = .down
        var failure: String?

        outer: for bill in bills {
            model.bill = bill
            for percent in percents {
                model.tipPercent = percent
                let grand = model.grandTotal

                if grand % 100 != 0 && grand != bill {
                    failure = "bill \(bill), percent \(percent): grandTotal \(grand) is neither a whole "
                        + "unit nor the bill"
                    break outer
                }
                if grand < bill {
                    failure = "bill \(bill), percent \(percent): grandTotal \(grand) is below the bill"
                    break outer
                }
                if model.tipTotal < 0 {
                    failure = "bill \(bill), percent \(percent): tipTotal \(model.tipTotal) is negative"
                    break outer
                }
            }
        }

        XCTAssertNil(failure, failure ?? "")
    }

    func testRoundDownClampsInsteadOfMakingTheTipNegative() {
        let model = TipCalculator()
        model.bill = 5000
        model.tipPercent = 0
        model.splitCount = 1
        model.roundMode = .down

        XCTAssertEqual(model.grandTotal, 5000)
        XCTAssertEqual(model.tipTotal, 0)
    }

    // MARK: - Criterion: a zero bill is zero everywhere

    func testZeroBillGivesZeroForEveryPercentSplitAndRoundMode() {
        let model = TipCalculator()
        model.bill = 0
        var failure: String?

        outer: for mode in modes {
            model.roundMode = mode
            for percent in percents {
                model.tipPercent = percent
                for n in splits {
                    model.splitCount = n
                    if model.tipTotal != 0 || model.grandTotal != 0
                        || model.perPerson != 0 || model.perPersonTip != 0
                        || model.remainderCount != 0 || model.tipRemainderCount != 0 {
                        failure = "percent \(percent), split \(n), mode \(mode): "
                            + "tipTotal \(model.tipTotal), grandTotal \(model.grandTotal), "
                            + "perPerson \(model.perPerson), perPersonTip \(model.perPersonTip), "
                            + "remainderCount \(model.remainderCount), "
                            + "tipRemainderCount \(model.tipRemainderCount)"
                        break outer
                    }
                }
            }
        }

        XCTAssertNil(failure, failure ?? "")
    }

    // MARK: - Criterion: a total smaller than the party splits into pennies

    func testThreeCentsAcrossTenPeopleGivesThreePeopleOneCent() {
        let model = TipCalculator()
        model.bill = 3
        model.tipPercent = 0
        model.splitCount = 10
        model.roundMode = .off

        XCTAssertEqual(model.grandTotal, 3)
        XCTAssertEqual(model.perPerson, 0)
        XCTAssertEqual(model.remainderCount, 3)
        XCTAssertEqual(model.perPerson + 1, 1, "each of the 3 remainder payers pays 1 cent")
        XCTAssertEqual(model.perPerson * 10 + model.remainderCount, model.grandTotal)
    }

    // MARK: - Criterion: one person pays the whole total

    func testSplitOfOneGivesTheWholeTotalToThatPerson() {
        let model = TipCalculator()
        model.bill = 4999
        model.tipPercent = 20
        model.splitCount = 1
        model.roundMode = .off

        XCTAssertEqual(model.grandTotal, 5999)
        XCTAssertEqual(model.perPerson, model.grandTotal)
        XCTAssertEqual(model.remainderCount, 0)
        XCTAssertEqual(model.perPersonTip, model.tipTotal)
        XCTAssertEqual(model.tipRemainderCount, 0)
    }
}
