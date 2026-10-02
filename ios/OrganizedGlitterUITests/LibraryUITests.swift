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

  func testIPhoneBrowsesTwoCraftsAndOpensPagesThroughBook() throws {
    try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone peer craft browsing.")
    let app = launch("populated")
    openLibrary(app)
    XCTAssertTrue(app.staticTexts["Garden of stars"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Diamond art"].exists)
    XCTAssertTrue(app.buttons["Coloring"].exists)
    XCTAssertFalse(app.buttons["Pages"].exists)
    XCTAssertTrue(app.buttons["create.menu"].exists)
    try capture(app, "library-diamonds")

    app.buttons["Coloring"].tap()
    let book = app.buttons.matching(
      NSPredicate(
        format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@",
        "Moonlit meadows",
        "24 pages"
      )
    ).firstMatch
    XCTAssertTrue(book.waitForExistence(timeout: 5))
    try capture(app, "library-books")

    book.tap()
    let page = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A moonlit garden")).firstMatch
    if !page.waitForExistence(timeout: 2) {
      app.swipeUp()
    }
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    try capture(app, "library-pages")
    page.tap()
    XCTAssertTrue(
      app.navigationBars["A moonlit garden with a very long, winding path"]
        .waitForExistence(timeout: 3))
  }

  func testColoringSearchFindsPagesAndCreateChoosesTheirBook() throws {
    let app = launch("populated")
    openLibrary(app)
    XCTAssertTrue(app.openCraft("Coloring"))
    app.buttons["create.menu"].tap()
    app.buttons["create.page"].tap()
    let book = app.buttons["Add pages to Moonlit meadows"]
    XCTAssertTrue(book.waitForExistence(timeout: 5))
    book.tap()
    XCTAssertTrue(app.textFields["pageCount.field"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].tap()

    XCTAssertTrue(app.openSearch())
    if app.segmentedControls.firstMatch.exists {
      app.segmentedControls.buttons["Coloring"].tap()
    } else {
      app.buttons["library.craft"].tap()
      app.buttons["Coloring"].tap()
    }
    XCTAssertTrue(app.navigationBars["Search"].exists)
    let search = app.searchFields.firstMatch
    if !search.waitForExistence(timeout: 2) {
      app.navigationBars["Search"].buttons["Search"].tap()
    }
    search.tap()
    search.typeText("moonlit\n")
    let page = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A moonlit garden")).firstMatch
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    page.tap()
    XCTAssertTrue(app.navigationBars["A moonlit garden with a very long, winding path"].waitForExistence(timeout: 5))
  }

  func testHomePageShortcutDoesNotReplaceColoringBooks() throws {
    try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone tab handoff.")
    let app = launch("populated")
    openLibrary(app)
    XCTAssertTrue(app.openCraft("Coloring"))
    XCTAssertTrue(app.staticTexts["Moonlit meadows"].waitForExistence(timeout: 5))
    app.tabBars.buttons["Home"].tap()
    app.buttons["overview.continue"].tap()
    app.buttons["Coloring pages in progress"].tap()
    XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A moonlit garden")).firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Coloring pages: In progress"].exists)
    app.buttons["library.clearPageSearchFilter"].tap()
    XCTAssertTrue(app.staticTexts["Search your library"].waitForExistence(timeout: 5))
    openLibrary(app)
    XCTAssertTrue(app.staticTexts["Moonlit meadows"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["A moonlit garden with a very long, winding path"].exists)
  }

  func testViewModesRememberEachCraftAndOpenDetails() throws {
    let app = launch("design")
    openLibrary(app)
    let modes = app.segmentedControls["library.viewMode"]
    XCTAssertTrue(modes.waitForExistence(timeout: 5))
    modes.buttons["List"].tap()
    XCTAssertTrue(modes.buttons["List"].isSelected)
    XCTAssertTrue(app.openCraft("Coloring"))
    modes.buttons["Compact"].tap()
    XCTAssertTrue(modes.buttons["Compact"].isSelected)
    XCTAssertTrue(app.openCraft("Diamond art"))
    XCTAssertTrue(modes.buttons["List"].isSelected)
    app.terminate()
    app.launch()
    openLibrary(app)
    XCTAssertTrue(modes.buttons["List"].waitForExistence(timeout: 5))
    XCTAssertTrue(modes.buttons["List"].isSelected)
    let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Yorkie & Roses,")).firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 5))
    XCTAssertTrue(card.label.contains("40×50"))
    XCTAssertTrue(card.label.contains("Started"))
    card.tap()
    XCTAssertTrue(app.buttons["detail.title"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    modes.buttons["Covers"].tap()
    XCTAssertTrue(app.openCraft("Coloring"))
    XCTAssertTrue(modes.buttons["Compact"].isSelected)
    modes.buttons["Covers"].tap()
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
        XCTAssertFalse(app.buttons["library.status"].exists)
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
    let books = app.craftRow("Coloring")
    if !books.waitForExistence(timeout: 2) {
      app.buttons["ToggleSideBar"].tap()
    }
    XCTAssertTrue(books.waitForExistence(timeout: 5))
    XCTAssertTrue(app.craftRow("Diamond art").exists)
    XCTAssertFalse(app.craftRow("Pages").exists)
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
      app.buttons["Coloring"].tap()
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

    let status = app.buttons["library.status"]
    XCTAssertEqual(status.value as? String, "All, 12")
    XCTAssertTrue(status.frame.maxX <= app.frame.maxX)
    XCTAssertTrue(app.buttons["library.sort"].frame.maxX <= app.frame.maxX)
    status.tap()
    XCTAssertTrue(app.buttons["In progress 2"].waitForExistence(timeout: 5))
    try capture(app, "library-status-menu")
    let completed = app.buttons["Completed 1"]
    for _ in 0..<6 where !completed.exists || !completed.isHittable {
      app.collectionViews.firstMatch.swipeUp()
    }
    completed.tap()
    XCTAssertTrue(app.staticTexts["Wildflowers"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Yorkie & Roses"].exists)
    XCTAssertEqual(status.value as? String, "Completed, 1")
    try capture(app, "library-status-filtered")

    status.tap()
    let all = app.buttons["All 12"]
    for _ in 0..<6 where !all.exists || !all.isHittable {
      app.collectionViews.firstMatch.swipeDown()
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

    XCTAssertTrue(app.openSearch(), "The Search destination is unavailable")
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
  func openSearch() -> Bool {
    let destination: XCUIElement
    if UIDevice.current.userInterfaceIdiom == .pad {
      destination = cells["Search"].firstMatch
      if !destination.exists || !destination.isHittable {
        let sidebar = buttons["ToggleSideBar"]
        guard sidebar.waitForExistence(timeout: 5), sidebar.isHittable else { return false }
        sidebar.tap()
      }
    } else {
      destination = tabBars.buttons["Search"].firstMatch
    }
    guard destination.waitForExistence(timeout: 5), destination.isHittable else { return false }
    destination.tap()
    return navigationBars["Search"].waitForExistence(timeout: 5)
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
