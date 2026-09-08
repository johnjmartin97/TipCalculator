import Foundation

/// Every string the totals screen shows, built once from the model. The screen
/// reads these and does no formatting of its own.
struct DisplayState {
    let billText: String
    let tipText: String
    let totalText: String
    let perPersonText: String
    /// Set only when the split leaves cents over: who pays the extra cent.
    let remainderText: String?

    init(model: TipCalculator, locale: Locale) {
        let money = CurrencyFormatter(locale: locale)

        billText = money.formatted(cents: model.billCents)
        tipText = money.formatted(cents: model.tipTotal)
        totalText = money.formatted(cents: model.grandTotal)
        perPersonText = money.formatted(cents: model.perPerson)

        let extra = model.remainderCount
        if extra == 0 {
            remainderText = nil
        } else {
            let higher = money.formatted(cents: model.perPerson + 1)
            let people = extra == 1 ? "person pays" : "people pay"
            remainderText = "\(extra) \(people) \(higher)"
        }
    }
}
