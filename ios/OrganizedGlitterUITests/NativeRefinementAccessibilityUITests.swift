import XCTest

@MainActor
final class NativeRefinementAccessibilityUITests: XCTestCase {
  func testCapturesLowerDetailLayoutsAtAccessibilityXXXL() throws {
    guard ProcessInfo.processInfo.environment["RUN_REFINEMENT_AX_CAPTURE"] == "1" else {
      throw XCTSkip(
        "Accessibility detail capture is opt-in; set RUN_REFINEMENT_AX_CAPTURE=1."
      )
    }

    let app = launchFixture()
    openLibrary(app)
    openCard(named: "Peony garden", in: app)
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))

    let addProgressPhoto = button("detail.diamond.addNote", in: app)
    makeHittable(addProgressPhoto, in: app)
    XCTAssertTrue(app.staticTexts["Photos"].exists)
    try capture("refinement-ax-01-diamond-lower")

    button("detail.edit", in: app).tap()
    let editor = app.navigationBars["Edit Project"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    try capture("refinement-ax-02-diamond-editor")
    editor.buttons["Cancel"].tap()
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))

    app.navigationBars.buttons.element(boundBy: 0).tap()
    selectCraft("Books", in: app)
    openCard(named: "Botanical days", in: app)
    XCTAssertTrue(element("detail.book", in: app).waitForExistence(timeout: 5))

    let editPageCount = button("detail.book.editPageCount", in: app)
    makeHittable(editPageCount, in: app)
    XCTAssertTrue(app.staticTexts["Pages"].exists)
    try capture("refinement-ax-03-book-pages")

    let firstPage = element("detail.book.page.design-page-0", in: app)
    makeHittable(firstPage, in: app)
    firstPage.tap()
    XCTAssertTrue(element("detail.page", in: app).waitForExistence(timeout: 5))

    let addPagePhoto = button("detail.page.addPhoto", in: app)
    makeHittable(addPagePhoto, in: app)
    XCTAssertTrue(app.staticTexts["Photos"].exists)
    try capture("refinement-ax-04-page-lower")
  }

  private func launchFixture() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing-authenticated", "-overview-fixture", "design"]
    app.launch()
    return app
  }

  private func openLibrary(_ app: XCUIApplication) {
    let tab = app.tabBars.buttons["Library"].firstMatch
    if tab.waitForExistence(timeout: 3) {
      tab.tap()
      return
    }

    for destination in [
      app.popUpButtons["Library"].firstMatch,
      app.buttons["Library"].firstMatch,
      app.staticTexts["Library"].firstMatch,
    ] where destination.exists && destination.isHittable {
      destination.tap()
      return
    }

    XCTFail("The Library destination is unavailable")
  }

  private func selectCraft(_ title: String, in app: XCUIApplication) {
    let directButton = app.buttons[title]
    if directButton.exists {
      directButton.tap()
      return
    }

    let craftMenu = app.buttons.matching(identifier: "library.craft").firstMatch
    if craftMenu.waitForExistence(timeout: 1) {
      craftMenu.tap()
      let option = app.buttons[title]
      XCTAssertTrue(option.waitForExistence(timeout: 5))
      option.tap()
      return
    }

    var sidebarRow = app.staticTexts[title]
    if !sidebarRow.exists {
      let showSidebar = app.buttons.matching(
        NSPredicate(
          format: "label ==[c] %@ OR label ==[c] %@",
          "Show Sidebar",
          "Toggle sidebar"
        )
      ).firstMatch
      if showSidebar.exists {
        showSidebar.tap()
      }
      sidebarRow = app.staticTexts[title]
    }

    XCTAssertTrue(sidebarRow.waitForExistence(timeout: 5))
    sidebarRow.tap()
  }

  private func openCard(named title: String, in app: XCUIApplication) {
    let card = app.buttons.matching(
      NSPredicate(format: "label CONTAINS[c] %@", title)
    ).firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 5))
    card.tap()
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  private func button(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(identifier: identifier).firstMatch
  }

  private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<10 where !element.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(element.isHittable)
  }

  private func capture(_ name: String) throws {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)

    if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      try screenshot.pngRepresentation.write(
        to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
      )
    }
  }
}
