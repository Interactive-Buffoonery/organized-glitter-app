import XCTest

@MainActor
final class StatsUITests: XCTestCase {
  func testStatsShowsServerTotalsAndChangesYear() {
    let app = launch("populated")
    openStats(app)
    XCTAssertTrue(app.otherElements.matching(NSPredicate(format: "label == %@", "Total kits")).firstMatch.waitForExistence(timeout: 5))
    let total = app.otherElements.matching(NSPredicate(format: "label == %@", "Total kits")).firstMatch
    XCTAssertEqual(total.value as? String, "24")
    let finished = app.otherElements.matching(NSPredicate(format: "label == %@", "Finished in 2026")).firstMatch
    XCTAssertEqual(finished.value as? String, "5")
    app.buttons["stats.year"].tap()
    app.buttons["2025"].tap()
    let previous = app.otherElements.matching(NSPredicate(format: "label == %@", "Finished in 2025")).firstMatch
    XCTAssertTrue(previous.waitForExistence(timeout: 5))
    XCTAssertEqual(previous.value as? String, "2")
  }

  func testStatsOfflineOffersRetry() {
    let app = launch("stats-offline")
    openStats(app)
    XCTAssertTrue(app.staticTexts["Stats need a connection"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Retry"].exists)
    app.buttons["Retry"].tap()
    XCTAssertTrue(app.staticTexts["Stats need a connection"].waitForExistence(timeout: 5))
  }

  private func launch(_ scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing-authenticated", "-overview-fixture", scenario]
    app.launch()
    return app
  }

  private func openStats(_ app: XCUIApplication) {
    XCTAssertTrue(app.openLibrary())
    let more = app.buttons["library.more"]
    XCTAssertTrue(more.waitForExistence(timeout: 5))
    more.tap()
    app.buttons["Stats"].tap()
    XCTAssertTrue(app.navigationBars["Stats"].waitForExistence(timeout: 5))
  }
}
