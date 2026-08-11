import XCTest
import SwiftUI
@testable import TipCalculator

/// Proves TIP-2: money is turned into text by the locale, not by hand, and the
/// totals screen reads its strings from one display state built off the model.
///
/// Every expected string below is written out as a literal. Nothing here asks
/// the code under test what the answer should be.
final class FormattingTests: XCTestCase {

    private let enUS = Locale(identifier: "en_US")
    private let deDE = Locale(identifier: "de_DE")

    // MARK: - Criterion: en_US formatting of whole cents

    func testFormatsCentsInUSEnglish() {
        let formatter = CurrencyFormatter(locale: enUS)

        XCTAssertEqual(formatter.formatted(cents: 4999), "$49.99")
        XCTAssertEqual(formatter.formatted(cents: 0), "$0.00")
        XCTAssertEqual(formatter.formatted(cents: 999999999), "$9,999,999.99")
    }

    // MARK: - Criterion: the symbol and separator come from the passed Locale

    func testGermanLocaleGivesCommaDecimalSeparatorAndEuroSymbol() {
        let formatter = CurrencyFormatter(locale: deDE)
        let text = formatter.formatted(cents: 4999)

        XCTAssertTrue(
            text.contains(","),
            "expected a comma decimal separator in de_DE, got \(text)"
        )
        XCTAssertTrue(
            text.contains("€"),
            "expected the euro symbol in de_DE, got \(text)"
        )
        XCTAssertFalse(
            text.contains("$"),
            "de_DE must not fall back to a hardcoded dollar sign, got \(text)"
        )
    }

    // MARK: - Criterion: the formatter takes Int cents only

    func testFormatterParameterTypeIsInt() {
        let formatter = CurrencyFormatter(locale: enUS)

        // If `formatted(cents:)` took anything but an Int, this binding would
        // not type-check, and the runtime check names the type it does take.
        let function: (Int) -> String = formatter.formatted(cents:)

        XCTAssertTrue(
            type(of: function) == ((Int) -> String).self,
            "formatted(cents:) is \(type(of: function)), not (Int) -> String"
        )
    }

    // MARK: - Criterion: display state for a single diner, no remainder

    func testDisplayStateForSingleDinerExposesEveryFormattedAmount() {
        let model = TipCalculator()
        model.bill = 4999
        model.tipPercent = 20
        model.splitCount = 1
        model.roundMode = .off

        let display = DisplayState(model: model, locale: enUS)

        XCTAssertEqual(display.billText, "$49.99")
        XCTAssertEqual(display.tipText, "$10.00")
        XCTAssertEqual(display.totalText, "$59.99")
        XCTAssertEqual(display.perPersonText, "$59.99")
        XCTAssertNil(display.remainderText, "one diner cannot have a remainder")
    }

    // MARK: - Criterion: display state names the people paying the extra cent

    func testDisplayStateNamesTheRemainderWhenTheSplitIsUneven() {
        let model = TipCalculator()
        model.bill = 1000
        model.tipPercent = 0
        model.splitCount = 3
        model.roundMode = .off

        let display = DisplayState(model: model, locale: enUS)

        XCTAssertEqual(display.perPersonText, "$3.33")

        guard let remainder = display.remainderText else {
            return XCTFail("$10.00 across 3 leaves one cent over; expected a remainder line")
        }
        XCTAssertTrue(
            remainder.contains("1"),
            "the remainder line must say how many people pay more, got \(remainder)"
        )
        XCTAssertTrue(
            remainder.contains("$3.34"),
            "the remainder line must show the higher share, got \(remainder)"
        )
    }

    // MARK: - Criterion: the root view builds from a model without crashing
    //
    // The other half of this criterion — that the app launches to the totals
    // screen — is proven by the existing launch UI test.

    @MainActor
    func testRootViewBuildsFromAModel() {
        let model = TipCalculator()
        model.bill = 4999

        let view = RootView(model: model)
        _ = view.body
    }
}
