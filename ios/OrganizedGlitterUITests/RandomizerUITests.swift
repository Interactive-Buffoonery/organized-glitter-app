import XCTest

@MainActor
final class RandomizerUITests: XCTestCase {
  func testLibraryPickOpensCurrentTargetAndKeepsNumberToolSeparate() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-authenticated", "-overview-fixture", "design"]
    app.launch()
    XCTAssertTrue(app.openLibrary())
    let more = app.buttons["library.more"]
    XCTAssertTrue(more.waitForExistence(timeout: 5))
    more.tap()
    app.buttons["library.pickForMe"].tap()
    let pick = app.buttons["pickForMe.pick"]
    XCTAssertTrue(pick.waitForExistence(timeout: 5))
    for _ in 0..<8 where !pick.isHittable { app.swipeUp() }
    XCTAssertTrue(pick.isEnabled)
    pick.tap()
    let open = app.buttons["pickForMe.open"]
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    for _ in 0..<5 where !open.isHittable { app.swipeUp() }
    XCTAssertTrue(open.isEnabled)
    open.tap()
    XCTAssertTrue(app.descendants(matching: .any)["detail.diamond"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(more.waitForExistence(timeout: 5))
    more.tap()
    app.buttons["library.pickSectionNumber"].tap()
    XCTAssertTrue(app.textFields["numberSectionInput"].waitForExistence(timeout: 5)
      || app.textViews["numberSectionInput"].exists)
    XCTAssertFalse(app.buttons["pickForMe.pick"].exists)
  }
}
