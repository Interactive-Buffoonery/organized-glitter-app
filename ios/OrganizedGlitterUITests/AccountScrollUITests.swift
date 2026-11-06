import XCTest

@MainActor
final class AccountScrollUITests: XCTestCase {
  /// The List-based Account screen crashed in UIKit's focus system on iPad after scrolling.
  func testAccountSurvivesScrollingToTheEnd() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-authenticated", "-overview-fixture", "design"]
    app.launch()
    XCTAssertTrue(app.buttons["account.open"].waitForExistence(timeout: 15))
    app.buttons["account.open"].tap()
    let list = app.scrollViews["account.list"]
    XCTAssertTrue(list.waitForExistence(timeout: 5))

    for _ in 0..<4 { list.swipeUp() }
    for _ in 0..<4 { list.swipeDown() }
    sleep(3)

    XCTAssertEqual(app.state, .runningForeground)
    XCTAssertTrue(list.exists)
  }
}
