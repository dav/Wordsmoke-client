import XCTest

@MainActor
final class WordsmokeUITests: XCTestCase {
  func testLaunchShowsTitle() {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.staticTexts["Wordsmoke"].exists)
  }
}
