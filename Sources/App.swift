import SwiftUI

@main
struct TipCalculatorApp: App {
    @State private var model = TipCalculator()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
