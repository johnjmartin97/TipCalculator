import XCTest
@testable import TipCalculator

/// Proves TIP-3: the keypad, the tip presets, the split stepper and the round
/// mode all drive the model, and every one of them recomputes the outputs on
/// the spot.
///
/// Every expected number below is written out as a literal, worked out by hand
/// from the brief's rounding rule. Nothing here asks the code under test what
/// the answer should be.
final class InputTests: XCTestCase {

    /// Taps a run of digits in order, left to right.
    private func tap(_ digits: [Int], on model: TipCalculator) {
        for digit in digits {
            model.tapDigit(digit)
        }
    }

    // MARK: - Criterion: digits shift in from the right

    func testTappingFourNineNineNineGivesFortyNineNinetyNine() {
        let model = TipCalculator()

        tap([4, 9, 9, 9], on: model)

        XCTAssertEqual(model.billCents, 4999)
    }

    // MARK: - Criterion: a leading zero leaves the bill empty

    func testTappingZeroOnAnEmptyBillLeavesItAtZero() {
        let model = TipCalculator()

        model.tapDigit(0)
        XCTAssertEqual(model.billCents, 0)

        // Anchor: a keypad that ignores every tap would also leave the bill at
        // zero, so prove the leading zero was dropped rather than the tap lost.
        model.tapDigit(5)
        XCTAssertEqual(model.billCents, 5, "the leading zero should not have been kept")

        tap([0, 0, 0], on: model)
        XCTAssertEqual(model.billCents, 5000, "zeros after the first digit are real digits")
    }

    // MARK: - Criterion: delete shifts right to left

    func testDeleteRemovesOneDigitFromTheRightEachTime() {
        let model = TipCalculator()
        tap([4, 9, 9, 9], on: model)

        model.tapDelete()
        XCTAssertEqual(model.billCents, 499)

        model.tapDelete()
        XCTAssertEqual(model.billCents, 49)
    }

    // MARK: - Criterion: delete on an empty bill is a no-op

    func testDeleteOnAnEmptyBillChangesNothing() {
        let model = TipCalculator()
        model.tipPercent = 18
        model.selectedPreset = 18
        model.splitCount = 4
        model.roundMode = .up

        // Anchor: a delete key that does nothing at all would also pass the
        // checks below, so prove it empties a real bill first.
        model.tapDigit(7)
        XCTAssertEqual(model.billCents, 7, "the bill must hold a digit before delete can empty it")
        model.tapDelete()
        XCTAssertEqual(model.billCents, 0, "deleting the only digit should empty the bill")

        let tipBefore = model.tipPercent
        let presetBefore = model.selectedPreset
        let customBefore = model.isCustomTip
        let splitBefore = model.splitCount
        let modeBefore = model.roundMode
        let totalBefore = model.grandTotal

        model.tapDelete()

        XCTAssertEqual(model.billCents, 0)
        XCTAssertEqual(model.tipPercent, tipBefore, "delete moved the tip percent")
        XCTAssertEqual(model.selectedPreset, presetBefore, "delete moved the selected preset")
        XCTAssertEqual(model.isCustomTip, customBefore, "delete moved the custom tip flag")
        XCTAssertEqual(model.splitCount, splitBefore, "delete moved the split count")
        XCTAssertEqual(model.roundMode, modeBefore, "delete moved the round mode")
        XCTAssertEqual(model.grandTotal, totalBefore, "delete moved the grand total")
    }

    // MARK: - Criterion: the bill stops at nine digits

    func testATenthDigitIsIgnoredOnceTheBillIsNineDigitsLong() {
        let model = TipCalculator()
        tap([9, 9, 9, 9, 9, 9, 9, 9, 9], on: model)
        XCTAssertEqual(model.billCents, 999999999, "nine 9s should fill the bill")

        model.tapDigit(1)
        XCTAssertEqual(model.billCents, 999999999, "a tenth digit must be ignored")

        model.tapDigit(0)
        XCTAssertEqual(model.billCents, 999999999, "a tenth digit must be ignored, zero included")
    }

    // MARK: - Criterion: the tip starts at the 20% preset

    func testAFreshModelStartsOnTheTwentyPercentPreset() {
        let model = TipCalculator()

        XCTAssertEqual(model.tipPercent, 20)
        XCTAssertEqual(model.selectedPreset, 20)
        XCTAssertTrue(model.isPresetSelected(20), "20 should be the selected preset")
        XCTAssertFalse(model.isCustomTip, "a fresh model is not on a custom tip")
    }

    // MARK: - Criterion: picking a preset selects exactly that one

    func testSelectingFifteenPercentMakesItTheOnlySelectedPreset() {
        let model = TipCalculator()
        model.setCustomTip(33)

        model.selectPreset(15)

        XCTAssertEqual(model.tipPercent, 15)
        XCTAssertEqual(model.selectedPreset, 15)
        XCTAssertFalse(model.isCustomTip, "picking a preset clears the custom flag")

        // The preset list is four values — small enough to check every one.
        for preset in TipCalculator.tipPresets {
            XCTAssertEqual(
                model.isPresetSelected(preset),
                preset == 15,
                "preset \(preset) selection is wrong after picking 15"
            )
        }
    }

    // MARK: - Criterion: a custom tip deselects every preset

    func testCustomTipLeavesNoPresetSelectedEvenWhenItEqualsAPreset() {
        let model = TipCalculator()

        model.setCustomTip(22)

        XCTAssertEqual(model.tipPercent, 22)
        XCTAssertNil(model.selectedPreset, "a custom tip has no preset")
        XCTAssertTrue(model.isCustomTip)
        for preset in TipCalculator.tipPresets {
            XCTAssertFalse(model.isPresetSelected(preset), "preset \(preset) selected on a custom tip")
        }

        // 20 is also a preset value, but typing it is still a custom tip.
        model.setCustomTip(20)

        XCTAssertEqual(model.tipPercent, 20)
        XCTAssertNil(model.selectedPreset, "typing 20 must not select the 20 preset")
        XCTAssertTrue(model.isCustomTip)
        for preset in TipCalculator.tipPresets {
            XCTAssertFalse(model.isPresetSelected(preset), "preset \(preset) selected after typing 20")
        }
    }

    // MARK: - Criterion: the custom tip clamps to 0...100 in whole steps

    func testCustomTipClampsToZeroThroughOneHundred() {
        let model = TipCalculator()

        model.setCustomTip(101)
        XCTAssertEqual(model.tipPercent, 100, "101 must clamp to 100")

        model.setCustomTip(-1)
        XCTAssertEqual(model.tipPercent, 0, "-1 must clamp to 0")

        model.setCustomTip(5000)
        XCTAssertEqual(model.tipPercent, 100)

        model.setCustomTip(-5000)
        XCTAssertEqual(model.tipPercent, 0)
    }

    func testEveryWholePercentFromZeroToOneHundredIsAcceptedExactly() {
        let model = TipCalculator()

        // 101 values is small enough to enumerate outright.
        for percent in 0...100 {
            model.setCustomTip(percent)
            XCTAssertEqual(model.tipPercent, percent, "custom tip \(percent) was not accepted as-is")
        }
    }

    func testCustomTipTakesWholeIntegersOnly() {
        let model = TipCalculator()

        // If `setCustomTip` took a fractional type this binding would not
        // type-check, and the runtime check names the type it does take.
        let step: (Int) -> Void = model.setCustomTip

        XCTAssertTrue(
            type(of: step) == ((Int) -> Void).self,
            "setCustomTip is \(type(of: step)), not (Int) -> Void"
        )
        XCTAssertTrue(type(of: model.tipPercent) == Int.self, "tipPercent is not Int")
    }

    // MARK: - Criterion: the split stepper runs 1 through 50 and stops at both ends

    func testSplitStartsAtOneAndWillNotGoLower() {
        let model = TipCalculator()

        XCTAssertEqual(model.splitCount, 1)
        XCTAssertFalse(model.canDecrementSplit, "the split cannot go below 1")

        model.decrementSplit()

        XCTAssertEqual(model.splitCount, 1, "decrementing at 1 must leave the split at 1")

        // Anchor: a stepper that never moves would also sit at 1 forever, so
        // prove the flag turns on once there is something to go back to.
        model.incrementSplit()
        XCTAssertEqual(model.splitCount, 2)
        XCTAssertTrue(model.canDecrementSplit, "decrement should be allowed at 2")

        model.decrementSplit()
        XCTAssertEqual(model.splitCount, 1, "decrement should come back down to 1")
    }

    func testFortyNineIncrementsReachFiftyAndTheSplitStopsThere() {
        let model = TipCalculator()

        // 50 values — enumerate the whole range and check both flags at each step.
        for step in 1...49 {
            XCTAssertTrue(model.canIncrementSplit, "increment should be allowed at \(model.splitCount)")
            XCTAssertEqual(
                model.canDecrementSplit,
                step > 1,
                "decrement flag is wrong at \(model.splitCount)"
            )
            model.incrementSplit()
            XCTAssertEqual(model.splitCount, step + 1, "increment \(step) landed on the wrong count")
        }

        XCTAssertEqual(model.splitCount, 50)
        XCTAssertFalse(model.canIncrementSplit, "the split cannot go above 50")
        XCTAssertTrue(model.canDecrementSplit)

        model.incrementSplit()

        XCTAssertEqual(model.splitCount, 50, "incrementing at 50 must leave the split at 50")
    }

    // MARK: - Criterion: round mode round-trips and the outputs follow
    //
    // Fixture: a $49.99 bill at 20%, split one way. The tip is 20% of 4999 =
    // 999.8 cents, which rounds half up to 1000, so the unrounded total is
    // 5999 — the same numbers TIP-1 asserts.

    func testRoundModeRoundTripsAndRecomputesTheTotals() {
        let model = TipCalculator()
        tap([4, 9, 9, 9], on: model)
        model.selectPreset(20)

        XCTAssertEqual(model.roundMode, .off, "a fresh model starts with rounding off")
        XCTAssertEqual(model.grandTotal, 5999)
        XCTAssertEqual(model.tipTotal, 1000)

        model.roundMode = .up
        XCTAssertEqual(model.grandTotal, 6000, "rounding up goes to the next whole dollar")
        XCTAssertEqual(model.tipTotal, 1001, "the tip absorbs the rounding")

        model.roundMode = .down
        XCTAssertEqual(model.grandTotal, 5900, "rounding down goes to the whole dollar below")
        XCTAssertEqual(model.tipTotal, 901)

        model.roundMode = .off
        XCTAssertEqual(model.grandTotal, 5999, "turning rounding off restores the exact total")
        XCTAssertEqual(model.tipTotal, 1000)
    }

    // MARK: - Criterion: every input recomputes the outputs synchronously

    func testGrandTotalReflectsEachDigitImmediatelyAfterTheTap() {
        let model = TipCalculator()
        model.selectPreset(20)

        // Bill after each tap, and the 20% total worked out by hand:
        //   4 -> tip 0.8 -> 1, total 5
        //   49 -> tip 9.8 -> 10, total 59
        //   499 -> tip 99.8 -> 100, total 599
        //   4999 -> tip 999.8 -> 1000, total 5999
        let expected: [(digit: Int, bill: Int, total: Int)] = [
            (4, 4, 5),
            (9, 49, 59),
            (9, 499, 599),
            (9, 4999, 5999),
        ]

        for step in expected {
            model.tapDigit(step.digit)
            XCTAssertEqual(model.billCents, step.bill, "bill is stale after tapping \(step.digit)")
            XCTAssertEqual(model.grandTotal, step.total, "total is stale after tapping \(step.digit)")
        }
    }

    func testEveryOtherInputAlsoRecomputesOnTheSameLine() {
        let model = TipCalculator()
        tap([4, 9, 9, 9], on: model)

        model.selectPreset(15)
        // 15% of 4999 = 749.85 -> 750, total 5749.
        XCTAssertEqual(model.grandTotal, 5749, "the preset did not recompute the total")

        model.setCustomTip(22)
        // 22% of 4999 = 1099.78 -> 1100, total 6099.
        XCTAssertEqual(model.grandTotal, 6099, "the custom tip did not recompute the total")

        model.incrementSplit()
        // 6099 across 2 people: 3049 each, one pays the odd cent.
        XCTAssertEqual(model.perPerson, 3049, "the split did not recompute the share")
        XCTAssertEqual(model.remainderCount, 1)

        model.decrementSplit()
        XCTAssertEqual(model.perPerson, 6099, "the split did not recompute back")

        model.tapDelete()
        // Bill 499, 22% = 109.78 -> 110, total 609.
        XCTAssertEqual(model.grandTotal, 609, "delete did not recompute the total")
    }
}
