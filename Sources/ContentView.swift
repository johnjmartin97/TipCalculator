import SwiftUI

/// Walking skeleton. The build loop replaces this with the real product.
struct ContentView: View {
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.067, blue: 0.086).ignoresSafeArea()
            Text("TipCalculator")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityIdentifier("app.title")
        }
    }
}

#Preview { ContentView() }
