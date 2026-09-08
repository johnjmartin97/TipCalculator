import Foundation

/// Turns whole cents into money text. The symbol, the grouping and the decimal
/// separator all come from the locale it is given; nothing here is hardcoded.
struct CurrencyFormatter {
    private let formatter: NumberFormatter

    init(locale: Locale) {
        formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
    }

    func formatted(cents: Int) -> String {
        let amount = Decimal(cents) / 100
        return formatter.string(from: amount as NSDecimalNumber) ?? ""
    }
}
