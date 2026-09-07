import XCTest

@MainActor
final class LibraryUITests: XCTestCase {
  private func launch(_ scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing-authenticated", "-overview-fixture", scenario]
    app.launch()
    return app
  }

  private func openLibrary(_ app: XCUIApplication) {
    let tabBarItem = app.tabBars.buttons["Library"]
    if tabBarItem.exists {
      tabBarItem.tap()
      return
    }
    let library = app.buttons["Library"].firstMatch
    XCTAssertTrue(library.waitForExistence(timeout: 5))
    library.tap()
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

  func testIPhoneBrowsesCraftsAsPeersAndOpensTheSameRecord() throws {
    try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone peer craft browsing.")
    let app = launch("populated")
    openLibrary(app)
    XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Garden of stars"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Diamond art"].exists)
    XCTAssertTrue(app.buttons["Books"].exists)
    XCTAssertTrue(app.buttons["Pages"].exists)
    XCTAssertFalse(app.navigationBars["Library"].buttons["Add"].exists)
    try capture(app, "library-diamonds")

    app.buttons["Books"].tap()
    XCTAssertTrue(app.staticTexts["Moonlit meadows"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Fictional Press"].exists)
    try capture(app, "library-books")

    app.buttons["Pages"].tap()
    let page = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "A moonlit garden")
    ).firstMatch
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    try capture(app, "library-pages")
    page.tap()
    XCTAssertTrue(
      app.navigationBars["A moonlit garden with a very long, winding path"]
        .waitForExistence(timeout: 3))
  }

  func testLoadingEmptyAndErrorStates() throws {
    for (scenario, label) in [
      ("loading", "Loading diamond projects"),
      ("empty", "Nothing here yet"),
      ("error", "Couldn’t load your library"),
    ] {
      let app = launch(scenario)
      openLibrary(app)
      XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5))
      XCTAssertFalse(app.navigationBars.buttons["Add"].exists)
      if scenario == "empty" {
        XCTAssertTrue(app.buttons["Add diamond painting project"].exists)
      }
      try capture(app, "library-\(scenario)")
      if scenario == "error" {
        app.buttons["Try Again"].tap()
        XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5))
      }
      app.terminate()
    }
  }

  func testIPadKeepsCraftSidebar() throws {
    guard UIDevice.current.userInterfaceIdiom == .pad else {
      throw XCTSkip("iPad sidebar review.")
    }
    let app = launch("populated")
    openLibrary(app)
    XCTAssertTrue(app.staticTexts["Garden of stars"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Diamond art"].exists)
    XCTAssertTrue(app.staticTexts["Books"].exists)
    XCTAssertTrue(app.staticTexts["Pages"].exists)
    XCTAssertFalse(app.segmentedControls.firstMatch.exists)
    XCTAssertFalse(app.navigationBars.buttons["Add"].exists)
    app.staticTexts["Books"].tap()
    XCTAssertTrue(app.staticTexts["Moonlit meadows"].waitForExistence(timeout: 5))
    try capture(app, "library-ipad-sidebar")
  }

  func testAccessibleCraftMenuAndRotation() throws {
    try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone craft menu.")
    let app = launch("populated")
    openLibrary(app)
    XCTAssertTrue(app.staticTexts["Garden of stars"].waitForExistence(timeout: 5))
    try capture(app, "library-accessibility-portrait")
    if !app.segmentedControls.firstMatch.exists {
      let picker = app.buttons["library.craft"]
      XCTAssertTrue(picker.exists)
      picker.tap()
      app.buttons["Books"].tap()
      XCTAssertTrue(app.staticTexts["Moonlit meadows"].waitForExistence(timeout: 3))
      XCTAssertFalse(app.staticTexts["Garden of stars"].exists)
      try capture(app, "library-accessibility-filtered")
    }
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    let landscape = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
    try capture(app, "library-accessibility-landscape")
  }
}
