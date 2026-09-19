import XCTest

@MainActor
final class NativeRefinementUITests: XCTestCase {
  func testCapturesSixApprovedScreensAndBookPageHierarchy() throws {
    let app = launchFixture()
    XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 5))
    try capture("refinement-01-overview")

    openLibrary(app)
    XCTAssertTrue(app.staticTexts["Peony garden"].waitForExistence(timeout: 5))
    try capture("refinement-02-diamond-gallery")

    openCard(named: "Peony garden", in: app)
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    try capture("refinement-03-diamond-detail")

    app.navigationBars.buttons.element(boundBy: 0).tap()
    selectCraft("Books", in: app)
    XCTAssertTrue(app.staticTexts["Botanical days"].waitForExistence(timeout: 5))
    try capture("refinement-04-book-gallery")

    openCard(named: "Botanical days", in: app)
    XCTAssertTrue(element("detail.book", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("detail.book.pages", in: app).waitForExistence(timeout: 5))
    try capture("refinement-05-book-detail")

    let page = element("detail.book.page.design-page-0", in: app)
    makeHittable(page, in: app)
    page.tap()
    XCTAssertTrue(element("detail.page", in: app).waitForExistence(timeout: 5))
    try capture("refinement-06-page-detail")
  }

  func testDiamondEditCancelSaveAndDeleteRemainStateful() {
    let app = launchFixture()
    openLibrary(app)
    openCard(named: "Peony garden", in: app)
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))

    element("detail.edit", in: app).tap()
    XCTAssertTrue(app.navigationBars["Edit Project"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Peony garden"].exists)

    element("detail.edit", in: app).tap()
    let title = app.textFields["Title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    replaceText(in: title, with: "Peony garden updated")
    app.buttons["Save"].tap()
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Peony garden updated"].waitForExistence(timeout: 5))

    element("detail.more", in: app).tap()
    element("detail.delete", in: app).tap()
    let confirmation = app.buttons["Delete Project"].lastMatch
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
    let addPhoto = element("detail.page.addPhoto", in: app)
    XCTAssertTrue(addPhoto.waitForExistence(timeout: 5))

    addPhoto.tap()
    let cancel = app.buttons["Cancel"].lastMatch
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
    let addPhoto = element("detail.page.addPhoto", in: app)
    XCTAssertTrue(addPhoto.waitForExistence(timeout: 5))
    let gallery = element("detail.photos", in: app)
    let initialPhotoCount = gallery.images.count
    addPhoto.tap()
    let photo = app.collectionViews.cells.firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 5))
    photo.tap()

    let detail = element("detail.page", in: app)
    let uploaded = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        detail.exists && gallery.images.count > initialPhotoCount
      },
      object: app
    )
    XCTAssertEqual(XCTWaiter.wait(for: [uploaded], timeout: 10), .completed)
  }

  private func launchFixture() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing-authenticated", "-overview-fixture", "design"]
    app.launch()
    return app
  }

  private func openLibrary(_ app: XCUIApplication) {
    let tab = app.tabBars.buttons["Library"]
    if tab.waitForExistence(timeout: 3) {
      tab.tap()
      return
    }
    let destination = app.buttons["Library"].firstMatch
    XCTAssertTrue(destination.waitForExistence(timeout: 5))
    destination.tap()
  }

  private func selectCraft(_ title: String, in app: XCUIApplication) {
    let craft = app.buttons[title]
    XCTAssertTrue(craft.waitForExistence(timeout: 5))
    craft.tap()
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
