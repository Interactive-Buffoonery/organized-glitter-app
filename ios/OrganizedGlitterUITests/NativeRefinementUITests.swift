import XCTest

@MainActor
final class NativeRefinementUITests: XCTestCase {
  func testCapturesSixApprovedScreensAndBookPageHierarchy() throws {
    let usesLandscape =
      ProcessInfo.processInfo.environment["SCREENSHOT_ORIENTATION"] == "landscape"
    if usesLandscape {
      XCUIDevice.shared.orientation = .landscapeLeft
    }
    defer {
      if usesLandscape {
        XCUIDevice.shared.orientation = .portrait
      }
    }

    let app = launchFixture()
    if usesLandscape {
      let landscape = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in app.frame.width > app.frame.height },
        object: app
      )
      XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
    }
    XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 5))
    try capture("refinement-01-overview")

    openLibrary(app)
    XCTAssertTrue(app.staticTexts["Peony garden"].waitForExistence(timeout: 5))
    try capture("refinement-02-diamond-gallery")

    openCard(named: "Peony garden", in: app)
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    assertArtworkLoaded("Project artwork", in: app)
    try capture("refinement-03-diamond-detail")

    app.navigationBars.buttons.element(boundBy: 0).tap()
    selectCraft("Books", in: app)
    XCTAssertTrue(app.staticTexts["Botanical days"].waitForExistence(timeout: 5))
    try capture("refinement-04-book-gallery")

    openCard(named: "Botanical days", in: app)
    XCTAssertTrue(element("detail.book", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("detail.book.pages", in: app).waitForExistence(timeout: 5))
    assertArtworkLoaded("Book cover", in: app)
    try capture("refinement-05-book-detail")

    let page = element("detail.book.page.design-page-0", in: app)
    makeHittable(page, in: app)
    page.tap()
    XCTAssertTrue(element("detail.page", in: app).waitForExistence(timeout: 5))
    assertArtworkLoaded("Page artwork", in: app)
    try capture("refinement-06-page-detail")
  }

  func testDiamondEditCancelSaveAndDeleteRemainStateful() {
    let app = launchFixture()
    openLibrary(app)
    openCard(named: "Peony garden", in: app)
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))

    button("detail.edit", in: app).tap()
    XCTAssertTrue(app.navigationBars["Edit Project"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Peony garden"].exists)

    button("detail.edit", in: app).tap()
    let title = app.textFields["Title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    replaceText(in: title, with: "Peony garden updated")
    app.buttons["Save"].tap()
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Peony garden updated"].waitForExistence(timeout: 5))

    button("detail.more", in: app).tap()
    button("detail.delete", in: app).tap()
    let confirmation = confirmationButton(named: "Delete Project", in: app)
    if confirmation.waitForExistence(timeout: 2) {
      confirmation.tap()
    }
    XCTAssertFalse(element("detail.diamond", in: app).waitForExistence(timeout: 3))
    XCTAssertFalse(app.staticTexts["Peony garden updated"].exists)
  }

  func testBookPagesPaginateAndNavigateToTheNextPage() {
    let app = launchFixture()
    openLibrary(app)
    selectCraft("Books", in: app)
    openCard(named: "Botanical days", in: app)
    XCTAssertTrue(element("detail.book", in: app).waitForExistence(timeout: 5))

    let loadMore = element("detail.book.loadMore", in: app)
    makeHittable(loadMore, in: app)
    loadMore.tap()
    let fifthPage = element("detail.book.page.design-page-4", in: app)
    makeHittable(fifthPage, in: app)
    fifthPage.tap()
    XCTAssertTrue(element("detail.page", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Page 5"].exists || app.navigationBars["Page 5"].exists)
  }

  func testPagePhotoPickerCanCancelWithoutChangingThePage() {
    let app = launchFixture()
    openFirstDesignPage(in: app)
    let addPhoto = button("detail.page.addPhoto", in: app)
    XCTAssertTrue(addPhoto.waitForExistence(timeout: 5))

    addPhoto.tap()
    let pickerCancel = app.navigationBars.buttons["Cancel"]
    let cancel = pickerCancel.exists
      ? pickerCancel : app.buttons.matching(identifier: "Cancel").firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    cancel.tap()
    XCTAssertTrue(element("detail.page", in: app).waitForExistence(timeout: 5))
  }

  func testPagePhotoPickerUploadsSeededPhoto() throws {
    guard ProcessInfo.processInfo.environment["RUN_PHOTO_PICKER_UPLOAD"] == "1" else {
      throw XCTSkip(
        "Photo selection is opt-in; seed the simulator with simctl addmedia and set RUN_PHOTO_PICKER_UPLOAD=1."
      )
    }

    let app = launchFixture()
    openFirstDesignPage(in: app)
    let addPhoto = button("detail.page.addPhoto", in: app)
    XCTAssertTrue(addPhoto.waitForExistence(timeout: 5))
    addPhoto.tap()
    let photo = app.collectionViews.cells.firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 5))
    photo.tap()

    let uploadedPhoto = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "Page photo 2: Moonlit garden")
    ).firstMatch
    XCTAssertTrue(uploadedPhoto.waitForExistence(timeout: 10))
    XCTAssertTrue(element("detail.page", in: app).exists)
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

    let destinations = [
      app.popUpButtons["Library"].firstMatch,
      app.buttons["Library"].firstMatch,
      app.staticTexts["Library"].firstMatch,
    ]
    for destination in destinations where destination.exists && destination.isHittable {
      destination.tap()
      return
    }

    XCTFail("The Library destination is unavailable")
  }

  private func selectCraft(_ title: String, in app: XCUIApplication) {
    let button = app.buttons[title]
    if button.exists {
      button.tap()
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

  private func openFirstDesignPage(in app: XCUIApplication) {
    openLibrary(app)
    selectCraft("Books", in: app)
    openCard(named: "Botanical days", in: app)
    let page = element("detail.book.page.design-page-0", in: app)
    makeHittable(page, in: app)
    page.tap()
    XCTAssertTrue(element("detail.page", in: app).waitForExistence(timeout: 5))
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  private func button(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(identifier: identifier).firstMatch
  }

  private func assertArtworkLoaded(_ label: String, in app: XCUIApplication) {
    let artwork = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", label)
    ).firstMatch
    XCTAssertTrue(artwork.waitForExistence(timeout: 5), "\(label) never finished loading")
  }

  private func confirmationButton(named label: String, in app: XCUIApplication) -> XCUIElement {
    let sheetButton = app.sheets.buttons[label]
    return sheetButton.exists
      ? sheetButton : app.buttons.matching(identifier: label).firstMatch
  }

  private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<8 where !element.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(element.isHittable)
  }

  private func replaceText(in field: XCUIElement, with value: String) {
    field.tap()
    if let current = field.value as? String, !current.isEmpty {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
    }
    field.typeText(value)
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
