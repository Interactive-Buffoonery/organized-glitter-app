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
    XCTAssertTrue(app.openLibrary(), "The Library destination is unavailable")
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
      ("empty", "Add your first kit"),
      ("error", "Couldn’t load your library"),
    ] {
      let app = launch(scenario)
      openLibrary(app)
      XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5))
      XCTAssertFalse(app.navigationBars.buttons["Add"].exists)
      if scenario == "empty" {
        XCTAssertTrue(app.buttons["create.menu"].exists)
        XCTAssertFalse(app.buttons["library.sort"].exists)
        XCTAssertFalse(app.buttons["library.status.all"].exists)
        app.buttons["library.first"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
      }
      try capture(app, "library-\(scenario)")
      if scenario == "error" {
        app.buttons["library.retry"].tap()
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
    let books = app.craftRow("Books")
    if !books.waitForExistence(timeout: 2) {
      app.buttons["ToggleSideBar"].tap()
    }
    XCTAssertTrue(books.waitForExistence(timeout: 5))
    XCTAssertTrue(app.craftRow("Diamond art").exists)
    XCTAssertTrue(app.craftRow("Pages").exists)
    XCTAssertTrue(app.cells["In progress, 5"].exists)
    XCTAssertTrue(app.cells["New coloring book"].exists)
    try capture(app, "library-ipad-sidebar")
    books.tap()
    XCTAssertTrue(app.staticTexts["Moonlit meadows"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["library.craft"].exists)
    XCTAssertTrue(app.buttons["create.menu"].exists)
    try capture(app, "library-ipad-books")
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

    let all = app.buttons["library.status.all"]
    let completed = app.buttons["library.status.completed"]
    let chipRow = all.frame.midY
    let origin = app.coordinate(withNormalizedOffset: .zero)
    for _ in 0..<4 where completed.frame.maxX > app.frame.maxX {
      origin.withOffset(CGVector(dx: 300, dy: chipRow)).press(
        forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 60, dy: chipRow)))
    }
    completed.tap()
    XCTAssertTrue(app.staticTexts["Wildflowers"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Yorkie & Roses"].exists)
    XCTAssertTrue(app.buttons["library.status.completed"].isSelected)
    try capture(app, "library-status-chips")

    for _ in 0..<4 where all.frame.minX < 0 {
      origin.withOffset(CGVector(dx: 60, dy: chipRow)).press(
        forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 300, dy: chipRow)))
    }
    all.tap()
    app.buttons["library.sort"].tap()
    app.buttons["Title A to Z"].tap()
    // All groups covers into status shelves; sort orders each shelf.
    XCTAssertTrue(
      app.descendants(matching: .any)["library.shelf.progress"].waitForExistence(timeout: 5))
    let divine = app.staticTexts["Divine Descent"]
    let yorkie = app.staticTexts["Yorkie & Roses"]
    XCTAssertTrue(divine.waitForExistence(timeout: 5))
    XCTAssertTrue(yorkie.exists)
    XCTAssertTrue(
      divine.frame.minY < yorkie.frame.minY
        || (divine.frame.minY == yorkie.frame.minY
          && divine.frame.minX < yorkie.frame.minX)
    )

    app.buttons["Search"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Search your library"].waitForExistence(timeout: 5))
    let search = app.searchFields.firstMatch
    // iPadOS collapses the field into a toolbar button at accessibility sizes.
    if !search.waitForExistence(timeout: 2) {
      app.navigationBars["Search"].buttons["Search"].tap()
    }
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    search.typeText("Divine\n")
    XCTAssertTrue(app.staticTexts["Divine Descent"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Beachside Gathering"].exists)
    try capture(app, "library-search")
  }
}

extension XCUIApplication {
  /// The iPad "All" row for a craft, labeled "All <craft>, <count>".
  func craftRow(_ craft: String) -> XCUIElement {
    descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", "All \(craft),")).firstMatch
  }

  @discardableResult
  func openLibrary() -> Bool {
    let tab = tabBars.buttons["Library"].firstMatch
    if tab.waitForExistence(timeout: 3) {
      tab.tap()
      return true
    }
    if openCraft("Diamond art") { return true }
    for destination in [
      popUpButtons["Library"].firstMatch,
      buttons["Library"].firstMatch,
      staticTexts["Library"].firstMatch,
    ] where destination.exists && destination.isHittable {
      destination.tap()
      return true
    }
    return false
  }

  @discardableResult
  func openCraft(_ craft: String) -> Bool {
    if UIDevice.current.userInterfaceIdiom == .pad {
      let row = craftRow(craft)
      if row.exists && row.isHittable {
        row.tap()
        return true
      }
    }
    let button = buttons[craft].firstMatch
    if button.waitForExistence(timeout: 3), button.isHittable {
      button.tap()
      return true
    }
    let menu = buttons.matching(identifier: "library.craft").firstMatch
    guard menu.waitForExistence(timeout: 5), menu.isHittable else { return false }
    menu.tap()
    guard button.waitForExistence(timeout: 5), button.isHittable else { return false }
    button.tap()
    return true
  }
}
