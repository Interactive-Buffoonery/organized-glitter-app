import XCTest

@MainActor
final class OverviewUITests: XCTestCase {
  private func launch(_ scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing-authenticated", "-overview-fixture", scenario]
    app.launch()
    return app
  }

  private func capture(_ app: XCUIApplication, _ name: String) throws {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
      try FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: true)
      try screenshot.pngRepresentation.write(
        to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
  }

  func testActiveWorkFilteringAndDetailNavigation() throws {
    let app = launch("populated")
    let page = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A moonlit garden"))
      .firstMatch
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    try capture(app, "overview-top")

    let segments = app.segmentedControls.firstMatch
    if segments.exists {
      segments.buttons["Diamond art"].tap()
      XCTAssertFalse(page.exists)
      segments.buttons["Coloring"].tap()
      XCTAssertTrue(page.waitForExistence(timeout: 3))
    }
    page.tap()
    XCTAssertTrue(
      app.navigationBars["A moonlit garden with a very long, winding path"]
        .waitForExistence(timeout: 3))
  }

  func testWishlistOpensFilteredLibrary() throws {
    let app = launch("populated")
    let wishlist = app.buttons["Wishlist"]
    XCTAssertTrue(wishlist.waitForExistence(timeout: 5))
    for _ in 0..<10 where !wishlist.isHittable { app.swipeUp() }
    XCTAssertTrue(wishlist.isHittable)
    try capture(app, "overview-bottom")
    wishlist.tap()
    app.buttons["Coloring book wishlist"].tap()
    XCTAssertTrue(app.navigationBars["Coloring books"].waitForExistence(timeout: 5))
    let filter = app.buttons["Filter by status"]
    XCTAssertTrue(filter.exists)
    filter.tap()
    XCTAssertTrue(app.buttons["Wishlist"].waitForExistence(timeout: 3))
  }

  func testAccessibleLayoutAndRotation() throws {
    let app = launch("populated")
    let page = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A moonlit garden"))
      .firstMatch
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    try capture(app, "overview-accessibility-portrait")
    if !app.segmentedControls.firstMatch.exists {
      let picker = app.buttons["overview.craft"]
      XCTAssertTrue(picker.exists)
      picker.tap()
      app.buttons["Coloring"].tap()
      XCTAssertTrue(page.waitForExistence(timeout: 3))
      XCTAssertFalse(
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Garden of stars"))
          .firstMatch.exists)
      app.swipeUp()
      try capture(app, "overview-accessibility-filtered")
      app.swipeDown()
    }
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    let landscape = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
    app.swipeUp()
    app.swipeDown()
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    try capture(app, "overview-accessibility-landscape")
  }

  func testReducedMotion() throws {
    guard ProcessInfo.processInfo.environment["RUN_SYSTEM_ACCESSIBILITY"] == "1" else {
      throw XCTSkip("System Settings review is opt-in; set RUN_SYSTEM_ACCESSIBILITY=1.")
    }
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launch()
    let accessibility = settings.staticTexts["Accessibility"]
    for _ in 0..<8 where !accessibility.isHittable { settings.swipeUp() }
    XCTAssertTrue(accessibility.isHittable)
    accessibility.tap()
    settings.staticTexts["Motion"].tap()
    let reduceMotion = settings.switches["Reduce Motion"]
    XCTAssertTrue(reduceMotion.waitForExistence(timeout: 5))
    let wasEnabled = reduceMotion.value as? String == "1"
    if !wasEnabled {
      reduceMotion.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }
    let enabled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == '1'"), object: reduceMotion)
    XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
    try capture(settings, "reduce-motion-setting")
    defer {
      if !wasEnabled {
        settings.activate()
        if reduceMotion.value as? String == "1" {
          reduceMotion.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
      }
    }
    let app = launch("populated")
    let page = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A moonlit garden"))
      .firstMatch
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    try capture(app, "overview-reduced-motion")
    page.tap()
    XCTAssertTrue(
      app.navigationBars["A moonlit garden with a very long, winding path"]
        .waitForExistence(timeout: 3))
  }

  func testLoadingEmptyAndErrorStates() throws {
    for (scenario, label) in [
      ("loading", "Loading your overview"),
      ("empty", "No work in progress"),
      ("error", "Couldn’t load your overview"),
    ] {
      let app = launch(scenario)
      XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5))
      try capture(app, "overview-\(scenario)")
      if scenario == "error" {
        app.buttons["Try Again"].tap()
        XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5))
      }
      app.terminate()
    }
  }
}
