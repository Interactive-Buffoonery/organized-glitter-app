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

  func testCraftingStreakTogglePersistsAndOpensNotes() throws {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing-authenticated", "-overview-fixture", "design",
    ]
    app.launch()
    XCTAssertTrue(app.buttons["account.open"].waitForExistence(timeout: 5))
    app.buttons["account.open"].tap()
    let toggle = app.switches["account.showCraftingStreak"]
    for _ in 0..<5 where !isOnScreen(toggle, in: app) || !toggle.isHittable { app.swipeUp() }
    XCTAssertTrue(toggle.isHittable)
    if toggle.value as? String == "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
    app.buttons["Done"].tap()
    XCTAssertFalse(app.buttons["home.craftingStreak"].exists)
    app.buttons["account.open"].tap()
    for _ in 0..<5 where !isOnScreen(toggle, in: app) || !toggle.isHittable { app.swipeUp() }
    toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    XCTAssertEqual(toggle.value as? String, "1")
    app.buttons["Done"].tap()
    let streak = app.buttons["home.craftingStreak"]
    XCTAssertTrue(streak.waitForExistence(timeout: 5))
    XCTAssertEqual(streak.label, "5-day crafting streak")
    XCTAssertTrue(isOnScreen(streak, in: app))
    streak.tap()
    XCTAssertTrue(app.buttons["notes.add"].waitForExistence(timeout: 5))
    app.terminate()
    app.launchArguments = ["-ui-testing-authenticated", "-overview-fixture", "design"]
    app.launch()
    XCTAssertTrue(streak.waitForExistence(timeout: 5))
    app.buttons["account.open"].tap()
    for _ in 0..<5 where !isOnScreen(toggle, in: app) || !toggle.isHittable { app.swipeUp() }
    toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    app.buttons["Done"].tap()
    XCTAssertTrue(streak.waitForNonExistence(timeout: 5))
  }

  func testNotesTabSharesNewLogsAndKeepsItsOwnDetailStack() throws {
    let app = launch("design")
    XCTAssertTrue(app.buttons["account.open"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["overview.notes"].exists)
    XCTAssertTrue(app.openNotes())
    XCTAssertTrue(app.buttons["notes.entry.design-page-note-1"].waitForExistence(timeout: 5))

    app.buttons["notes.add"].tap()
    let target = app.buttons["notes.target.design-project-0"]
    XCTAssertTrue(target.waitForExistence(timeout: 5))
    target.tap()
    let caption = app.descendants(matching: .any)
      .matching(NSPredicate(format: "placeholderValue == %@", "Caption (optional)")).firstMatch
    XCTAssertTrue(caption.waitForExistence(timeout: 5))
    caption.tap()
    caption.typeText("Logged from the Notes tab")
    app.buttons["detail.progress.noteSubmit"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["detail.progress.noteEditor"]
      .waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Logged from the Notes tab"].waitForExistence(timeout: 5))

    let entry = app.buttons["notes.entry.design-note-1"]
    for _ in 0..<5 where !entry.isHittable { app.swipeUp() }
    XCTAssertTrue(entry.isHittable)
    entry.tap()
    XCTAssertTrue(app.descendants(matching: .any)["detail.diamond"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.openSearch())
    XCTAssertTrue(app.staticTexts["Search your library"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.openNotes())
    XCTAssertTrue(app.descendants(matching: .any)["detail.diamond"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.buttons["notes.add"].waitForExistence(timeout: 5))
  }

  func testHomeLogAppearsInNotesTab() throws {
    let app = launch("design")
    XCTAssertTrue(app.openNotes())
    XCTAssertTrue(app.buttons["notes.entry.design-page-note-1"].waitForExistence(timeout: 5))
    let home = UIDevice.current.userInterfaceIdiom == .pad
      ? app.cells["Home"].firstMatch : app.tabBars.buttons["Home"].firstMatch
    if !home.isHittable, app.buttons["ToggleSideBar"].exists {
      app.buttons["ToggleSideBar"].tap()
    }
    XCTAssertTrue(home.waitForExistence(timeout: 5))
    home.tap()
    let log = app.buttons["overview.log.design-project-0"]
    XCTAssertTrue(log.waitForExistence(timeout: 5))
    for _ in 0..<5 where !log.isHittable { app.swipeUp() }
    log.tap()
    let caption = app.descendants(matching: .any)
      .matching(NSPredicate(format: "placeholderValue == %@", "Caption (optional)")).firstMatch
    XCTAssertTrue(caption.waitForExistence(timeout: 5))
    caption.tap()
    caption.typeText("Logged from Home")
    app.buttons["detail.progress.noteSubmit"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["detail.progress.noteEditor"]
      .waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.openNotes())
    XCTAssertTrue(app.staticTexts["Logged from Home"].waitForExistence(timeout: 5))
  }

  func testPickUpOpensDetailAndLogsProgress() throws {
    let app = launch("populated")
    XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
    let hero = app.buttons["overview.hero"]
    XCTAssertTrue(hero.waitForExistence(timeout: 5))
    XCTAssertTrue(hero.label.contains("Garden of stars"))
    XCTAssertTrue(hero.label.contains("Finished the first section."))
    let page = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A moonlit garden"))
      .firstMatch
    XCTAssertTrue(page.exists)
    XCTAssertFalse(app.staticTexts["Wishlist garden"].exists)
    try capture(app, "overview-top")

    let log = app.buttons["overview.log.fictional-project-1"]
    XCTAssertEqual(log.label, "Log progress for Garden of stars")
    log.tap()
    XCTAssertTrue(app.descendants(matching: .any)["detail.progress.noteEditor"].waitForExistence(timeout: 5))
    try capture(app, "overview-log-sheet")
    app.buttons["Cancel"].tap()

    let logRow = app.buttons["overview.log.fictional-project-2"]
    for _ in 0..<5 where !logRow.isHittable { app.swipeUp() }
    logRow.tap()
    let caption = app.descendants(matching: .any)
      .matching(NSPredicate(format: "placeholderValue == %@", "Caption (optional)")).firstMatch
    XCTAssertTrue(caption.waitForExistence(timeout: 5))
    caption.tap()
    caption.typeText("Filled the corner")
    app.buttons["detail.progress.noteSubmit"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["detail.progress.noteEditor"].waitForNonExistence(timeout: 5))
    let promoted = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label CONTAINS %@", "Filled the corner"), object: hero)
    XCTAssertEqual(XCTWaiter.wait(for: [promoted], timeout: 5), .completed)
    XCTAssertTrue(hero.label.contains("chapter 2"))

    for _ in 0..<5 where !page.isHittable { app.swipeUp() }
    page.tap()
    XCTAssertTrue(
      app.navigationBars["A moonlit garden with a very long, winding path"]
        .waitForExistence(timeout: 3))
  }

  func testEmptyHomeOpensTheStash() throws {
    let app = launch("empty")
    let stash = app.buttons["overview.stash"]
    XCTAssertTrue(stash.waitForExistence(timeout: 5))
    stash.tap()
    assertOpenedShelf("In stash", in: app)
  }

  /// iPad opens the shelf's own sidebar row; iPhone selects its status.
  private func assertOpenedShelf(_ title: String, in app: XCUIApplication) {
    if UIDevice.current.userInterfaceIdiom == .pad {
      XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
      return
    }
    let menu = app.buttons["library.status"]
    XCTAssertTrue(menu.waitForExistence(timeout: 5))
    XCTAssertTrue((menu.value as? String)?.hasPrefix("\(title),") == true)
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
      ("empty", "Nothing in progress"),
      ("error", "Couldn’t load your overview"),
    ] {
      let app = launch(scenario)
      XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5))
      try capture(app, "overview-\(scenario)")
      if scenario == "error" {
        app.buttons["overview.retry"].tap()
        XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5))
      }
      app.terminate()
    }
  }
}
