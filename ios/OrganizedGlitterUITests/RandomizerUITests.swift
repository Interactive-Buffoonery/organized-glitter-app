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
    XCTAssertTrue(app.navigationBars["Randomizer"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.sheets.count, 0)
    let page = XCTAttachment(screenshot: app.screenshot())
    page.name = "Classic Randomizer page"
    page.lifetime = .keepAlways
    add(page)
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
    XCTAssertTrue(app.navigationBars["Randomizer"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["pickForMe.open"].exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(more.waitForExistence(timeout: 5))
    more.tap()
    app.buttons["library.pickSectionNumber"].tap()
    XCTAssertTrue(app.textFields["numberSectionInput"].waitForExistence(timeout: 5)
      || app.textViews["numberSectionInput"].exists)
    XCTAssertFalse(app.buttons["pickForMe.pick"].exists)
  }

  func testClassicPageSelectionUsesAllNoneAndCurrentItemIDs() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-authenticated", "-overview-fixture", "design"]
    app.launch()
    XCTAssertTrue(app.openLibrary())
    app.buttons["library.more"].tap()
    app.buttons["library.pickForMe"].tap()
    let none = app.buttons["pickForMe.selectNone"]
    XCTAssertTrue(none.waitForExistence(timeout: 5))
    for _ in 0..<8 where !none.isHittable { app.swipeUp() }
    none.tap()
    let pick = app.buttons["pickForMe.pick"]
    XCTAssertFalse(pick.isEnabled)
    let item = app.switches["pickForMe.item.diamond:design-project-0"]
    for _ in 0..<5 where !item.isHittable { app.swipeUp() }
    XCTAssertTrue(item.isHittable)
    XCTAssertEqual(item.value as? String, "0")
    item.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    XCTAssertEqual(item.value as? String, "1")
    let search = app.textFields["pickForMe.search"]
    for _ in 0..<8 where !search.isHittable { app.swipeDown() }
    search.tap()
    search.typeText("no-matching-title")
    XCTAssertTrue(app.staticTexts["No items match your search."].exists)
    XCTAssertTrue(pick.isEnabled)
    search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 17))
    XCTAssertTrue(item.exists)
    app.swipeDown()
    for _ in 0..<8 where !pick.isHittable { app.swipeDown() }
    XCTAssertTrue(pick.isEnabled)
    pick.tap()
    let open = app.buttons["pickForMe.open"]
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    for _ in 0..<5 where !open.isHittable { app.swipeUp() }
    open.tap()
    XCTAssertTrue(app.staticTexts["Summer Garden Blooms"].waitForExistence(timeout: 5))
  }

  func testClassicWheelAcceptsSkipWhileSpinning() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-authenticated", "-overview-fixture", "design"]
    app.launch()
    XCTAssertTrue(app.openLibrary())
    app.buttons["library.more"].tap()
    app.buttons["library.pickForMe"].tap()
    let pick = app.buttons["pickForMe.pick"]
    XCTAssertTrue(pick.waitForExistence(timeout: 5))
    for _ in 0..<8 where !pick.isHittable { app.swipeUp() }
    pick.doubleTap()
    let open = app.buttons["pickForMe.open"]
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    XCTAssertTrue(open.isEnabled)
    XCTAssertTrue(pick.isEnabled)
    XCTAssertEqual(app.sheets.count, 0)
  }

  func testSavedHistorySurvivesClearAndReopensCurrentTarget() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-authenticated", "-overview-fixture", "design"]
    app.launch()
    XCTAssertTrue(app.openLibrary())
    app.buttons["library.more"].tap()
    app.buttons["library.pickForMe"].tap()
    let pick = app.buttons["pickForMe.pick"]
    XCTAssertTrue(pick.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["What will you work on next?"].exists)
    pick.doubleTap()
    let open = app.buttons["pickForMe.open"]
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "pickForMe.history.fixture-randomizer_spins-"))
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(rows.count, 1)
    let clear = app.buttons["Clear result"]
    for _ in 0..<8 where !clear.isHittable { app.swipeUp() }
    XCTAssertTrue(clear.isHittable)
    clear.tap()
    XCTAssertFalse(open.exists)
    XCTAssertEqual(rows.count, 1)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["library.more"].tap()
    app.buttons["library.pickForMe"].tap()
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    for _ in 0..<8 where !rows.firstMatch.isHittable { app.swipeUp() }
    let history = XCTAttachment(screenshot: app.screenshot())
    history.name = "Classic Randomizer saved history"
    history.lifetime = .keepAlways
    add(history)
    rows.firstMatch.tap()
    XCTAssertTrue(app.descendants(matching: .any)["detail.diamond"].waitForExistence(timeout: 5))
  }

}
