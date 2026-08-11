import XCTest

/// Proves the app launches on a real simulator and renders its first screen.
final class LaunchUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.staticTexts["app.title"].waitForExistence(timeout: 20),
            "the app launched and rendered its title"
        )
    }
}
