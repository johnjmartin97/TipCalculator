import SwiftUI

@main
struct TipCalculatorApp: App {
    private let model = TipCalculator()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
