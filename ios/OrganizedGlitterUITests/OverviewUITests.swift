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

  private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    element.exists && !element.frame.isEmpty && app.frame.contains(element.frame)
  }

  func testContinueOpensDetailAndLogsProgress() throws {
    let app = launch("populated")
    let page = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A moonlit garden"))
      .firstMatch
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Logged"))
        .firstMatch.waitForExistence(timeout: 5))
    try capture(app, "overview-top")

    let log = app.buttons["overview.log.fictional-project-1"]
    XCTAssertTrue(log.exists)
    XCTAssertEqual(log.label, "Log progress for Garden of stars")
    log.tap()
    XCTAssertTrue(app.descendants(matching: .any)["detail.diamond.noteEditor"].waitForExistence(timeout: 5))
    try capture(app, "overview-log-sheet")
    app.buttons["Cancel"].tap()

    let shelf = app.scrollViews["overview.continue.shelf"]
    let logLast = app.buttons["overview.log.fictional-project-2"]
    for _ in 0..<6 where !isOnScreen(logLast, in: app) { shelf.swipeLeft() }
    logLast.tap()
    let caption = app.descendants(matching: .any)
      .matching(NSPredicate(format: "placeholderValue == %@", "Caption (optional)")).firstMatch
    XCTAssertTrue(caption.waitForExistence(timeout: 5))
    caption.tap()
    caption.typeText("Filled the corner")
    app.buttons["detail.diamond.noteSubmit"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["detail.diamond.noteEditor"].waitForNonExistence(timeout: 5))
    let moved = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        self.isOnScreen(logLast, in: app) && logLast.frame.minX < log.frame.minX
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Logged today"))
        .firstMatch.exists)

    page.tap()
    XCTAssertTrue(
      app.navigationBars["A moonlit garden with a very long, winding path"]
        .waitForExistence(timeout: 3))
  }

  func testUpNextOpensTheStashFilter() throws {
    let app = launch("design")
    let upNext = app.buttons["overview.upNext"]
    XCTAssertTrue(upNext.waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label == %@", "Beachside Gathering, In stash"))
        .firstMatch.exists)
    try capture(app, "overview-bottom")
    upNext.tap()
    app.buttons["In stash"].tap()
    let stash = app.buttons["library.status.stash"]
    XCTAssertTrue(stash.waitForExistence(timeout: 5))
    XCTAssertTrue(stash.isSelected)
    XCTAssertTrue(app.staticTexts["Beachside Gathering"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Yorkie & Roses"].exists)
  }

  func testCompletedShortcutOpensTheSelectedLibraryFilter() throws {
    let app = launch("design")
    let finished = app.buttons["overview.finished"]
    XCTAssertTrue(finished.waitForExistence(timeout: 5))
    for _ in 0..<5 where !finished.isHittable { app.swipeUp() }
    finished.tap()
    app.buttons["Completed diamond art"].tap()

    XCTAssertTrue(app.buttons["library.status.completed"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["library.status.completed"].isSelected)
    XCTAssertTrue(app.staticTexts["Wildflowers"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Yorkie & Roses"].exists)
  }

  func testAccessibleLayoutAndRotation() throws {
    let app = launch("populated")
    let page = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A moonlit garden"))
      .firstMatch
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    try capture(app, "overview-accessibility-portrait")
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    // iPadOS 26 can run the app windowed, where its frame ignores rotation.
    if UIDevice.current.userInterfaceIdiom == .phone {
      let landscape = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: app)
      XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
    }
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
