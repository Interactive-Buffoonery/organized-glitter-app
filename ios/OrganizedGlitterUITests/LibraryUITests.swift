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
    XCTAssertTrue(app.staticTexts["Garden of stars"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Diamond art"].exists)
    XCTAssertTrue(app.buttons["Books"].exists)
    XCTAssertTrue(app.buttons["Pages"].exists)
    XCTAssertTrue(app.buttons["create.menu"].exists)
    try capture(app, "library-diamonds")

    app.buttons["Books"].tap()
    let book = app.buttons.matching(
      NSPredicate(
        format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@",
        "Moonlit meadows",
        "24 pages"
      )
    ).firstMatch
    XCTAssertTrue(book.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["create.menu"].exists)
      }
      try capture(app, "library-\(scenario)")
      if scenario == "error" {
        app.buttons["Try Again"].tap()
        XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5))
      }
      app.terminate()
    }
  }

  func testIPadListsCraftsInOneSidebar() throws {
    guard UIDevice.current.userInterfaceIdiom == .pad else {
      throw XCTSkip("iPad sidebar review.")
    }
    let app = launch("populated")
    let books = app.cells["Books"]
    if !books.waitForExistence(timeout: 2) {
      app.buttons["ToggleSideBar"].tap()
    }
    XCTAssertTrue(books.waitForExistence(timeout: 5))
    XCTAssertTrue(app.cells["Diamond art"].exists)
    XCTAssertTrue(app.cells["Pages"].exists)
    books.tap()
    XCTAssertTrue(app.staticTexts["Moonlit meadows"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["library.craft"].exists)
    XCTAssertTrue(app.buttons["create.menu"].exists)
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

  func testSearchStatusAndSortUseServerBackedControls() throws {
    let app = launch("design")
    openLibrary(app)
    XCTAssertTrue(app.staticTexts["Yorkie & Roses"].waitForExistence(timeout: 5))

    app.buttons["library.status"].tap()
    app.buttons["Completed"].tap()
    XCTAssertTrue(app.staticTexts["Wildflowers"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Yorkie & Roses"].exists)

    app.buttons["library.status"].tap()
    app.buttons["All statuses"].tap()
    app.buttons["library.sort"].tap()
    app.buttons["Title A to Z"].tap()
    let beachside = app.staticTexts["Beachside Gathering"]
    let divine = app.staticTexts["Divine Descent"]
    XCTAssertTrue(beachside.waitForExistence(timeout: 5))
    XCTAssertTrue(divine.exists)
    XCTAssertTrue(
      beachside.frame.minY < divine.frame.minY
        || (beachside.frame.minY == divine.frame.minY
          && beachside.frame.minX < divine.frame.minX)
    )

    app.buttons["Search"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Search your library"].waitForExistence(timeout: 5))
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    search.typeText("Divine\n")
    XCTAssertTrue(app.staticTexts["Divine Descent"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Beachside Gathering"].exists)
    try capture(app, "library-search")
  }
}
