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
    XCTAssertTrue(app.buttons["create.menu"].waitForExistence(timeout: 5))
    try capture("refinement-01-overview")

    openLibrary(app)
    XCTAssertTrue(app.staticTexts["Peony Garden"].waitForExistence(timeout: 5))
    try capture("refinement-02-diamond-gallery")

    openCard(named: "Peony Garden", in: app)
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    assertArtworkLoaded("Project artwork", in: app)
    try capture("refinement-03-diamond-detail")

    app.navigationBars.buttons.element(boundBy: 0).tap()
    selectCraft("Coloring", in: app)
    XCTAssertTrue(app.staticTexts["Garden Friends"].waitForExistence(timeout: 5))
    try capture("refinement-04-book-gallery")

    openCard(named: "Garden Friends", in: app)
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

  func testCapturesShellActions() throws {
    let app = launchFixture()
    XCTAssertTrue(app.buttons["create.menu"].waitForExistence(timeout: 5))

    app.buttons["create.menu"].tap()
    XCTAssertTrue(app.buttons["create.diamond"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["create.book"].exists)
    try capture("shell-01-create-menu")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()

    app.buttons["account.open"].tap()
    XCTAssertTrue(app.staticTexts["Profile name"].waitForExistence(timeout: 3))
    try capture("shell-02-account")
    app.buttons["Done"].tap()

    XCTAssertTrue(app.openSearch(), "The Search destination is unavailable")
    XCTAssertTrue(app.staticTexts["Search your library"].waitForExistence(timeout: 5))
    try capture("shell-03-search")
  }

  func testSyncStatusKeepsNavigationAvailable() {
    for scenario in ["loading", "error"] {
      let app = launchFixture(scenario: scenario)
      let status = element("library.syncStatus", in: app)
      XCTAssertTrue(status.waitForExistence(timeout: 5), "Missing sync status for \(scenario)")

      let libraryTab = app.tabBars.buttons["Library"].firstMatch
      if libraryTab.exists {
        XCTAssertTrue(libraryTab.isHittable, "Library tab is covered during \(scenario)")
      }
      openLibrary(app)
      XCTAssertTrue(
        app.navigationBars["Library"].waitForExistence(timeout: 5)
          || app.navigationBars["Diamond art"].exists,
        "Library cannot be opened during \(scenario)")
      app.terminate()
    }
  }

  func testDiamondEditCancelSaveAndDeleteRemainStateful() {
    let app = launchFixture()
    openLibrary(app)
    openCard(named: "Peony Garden", in: app)
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))

    button("detail.edit", in: app).tap()
    XCTAssertTrue(app.navigationBars["Edit Project"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Peony Garden"].exists)

    button("detail.edit", in: app).tap()
    let title = app.textFields["Title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    replaceText(in: title, with: "Peony Garden updated", app: app)
    app.buttons["Save"].tap()
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Peony Garden updated"].waitForExistence(timeout: 5))

    button("detail.more", in: app).tap()
    button("detail.delete", in: app).tap()
    let confirmation = confirmationButton(named: "Delete Project", in: app)
    if confirmation.waitForExistence(timeout: 2) {
      confirmation.tap()
    }
    XCTAssertFalse(element("detail.diamond", in: app).waitForExistence(timeout: 3))
    XCTAssertFalse(app.staticTexts["Peony Garden updated"].exists)
  }

  func testDiamondDetailShowsSpecsDetailsAndChangesStatus() throws {
    let app = launchFixture()
    openLibrary(app)
    openCard(named: "Peony Garden", in: app)
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("detail.specs", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(button("detail.progress.addNote", in: app).exists)
    let photo = app.images.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Progress photo from")
    ).firstMatch
    for _ in 0..<6 where !photo.waitForExistence(timeout: 1) {
      app.swipeUp()
    }
    XCTAssertTrue(photo.exists)

    let status = button("detail.status", in: app)
    for _ in 0..<6 where !status.isHittable {
      app.swipeDown()
    }
    XCTAssertEqual(status.value as? String, "In progress")
    status.tap()
    let completed = app.buttons["Completed"].firstMatch
    XCTAssertTrue(completed.waitForExistence(timeout: 3))
    completed.tap()
    let changed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "Completed"), object: status)
    XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)

    let source = element("detail.diamond.source", in: app)
    makeHittable(source, in: app)
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Florals and Gardens"))
        .firstMatch.exists)
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Soft pink peonies"))
        .firstMatch.exists)
    try capture("detail-diamond-lower")
  }

  func testPhotoViewerOpensCoverAndPagesProgressPhotos() {
    let app = launchFixture()
    openLibrary(app)
    openCard(named: "Peony Garden", in: app)
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))

    let cover = element("detail.hero", in: app)
    makeHittable(cover, in: app)
    cover.tap()
    XCTAssertTrue(element("photoViewer.image", in: app).waitForExistence(timeout: 5))
    button("photoViewer.close", in: app).tap()
    XCTAssertTrue(element("photoViewer", in: app).waitForNonExistence(timeout: 5))

    app.scrollViews["detail.diamond"].swipeUp()
    let photo = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Open progress photo from")
    ).firstMatch
    makeHittable(photo, in: app)
    photo.tap()
    XCTAssertTrue(element("photoViewer.image", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(button("photoViewer.next", in: app).isEnabled)
    button("photoViewer.next", in: app).tap()
    XCTAssertTrue(button("photoViewer.previous", in: app).isEnabled)
    button("photoViewer.close", in: app).tap()
    XCTAssertTrue(element("detail.diamond", in: app).exists)
  }

  func testPageArtworkAndPhotoOpenFullScreen() {
    let app = launchFixture()
    openFirstDesignPage(in: app)

    let cover = element("detail.hero", in: app)
    makeHittable(cover, in: app)
    cover.tap()
    XCTAssertTrue(element("photoViewer.image", in: app).waitForExistence(timeout: 5))
    button("photoViewer.close", in: app).tap()
    XCTAssertTrue(element("photoViewer", in: app).waitForNonExistence(timeout: 5))

    let photo = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Open Page photo")
    ).firstMatch
    let pageScroll = app.scrollViews.containing(.button, identifier: "detail.page.addPhoto").firstMatch
    for _ in 0..<8 where !photo.isHittable {
      pageScroll.swipeUp()
    }
    XCTAssertTrue(photo.isHittable)
    photo.tap()
    XCTAssertTrue(element("photoViewer.image", in: app).waitForExistence(timeout: 5))
    button("photoViewer.close", in: app).tap()
    XCTAssertTrue(element("detail.page", in: app).exists)
  }

  func testBookPagesPaginateAndNavigateToTheNextPage() {
    let app = launchFixture(scenario: "many-pages")
    openLibrary(app)
    selectCraft("Coloring", in: app)
    openCard(named: "Garden Friends", in: app)
    XCTAssertTrue(element("detail.book", in: app).waitForExistence(timeout: 5))

    let loadMore = element("detail.book.loadMore", in: app)
    makeHittable(loadMore, in: app)
    loadMore.tap()
    let twentyFifthPage = element("detail.book.page.design-page-24", in: app)
    makeHittable(twentyFifthPage, in: app)
    twentyFifthPage.tap()
    XCTAssertTrue(element("detail.page", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Page 25"].exists || app.navigationBars["Page 25"].exists)
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
    let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 5))
    photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

    let confirm = button("detail.page.photoSubmit", in: app)
    XCTAssertTrue(confirm.waitForExistence(timeout: 10))
    confirm.tap()

    let uploadedPhoto = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "Page photo 2: Hedgehog")
    ).firstMatch
    XCTAssertTrue(uploadedPhoto.waitForExistence(timeout: 10))
    XCTAssertTrue(element("detail.page", in: app).exists)
  }

  private func launchFixture(scenario: String = "design") -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing-authenticated", "-overview-fixture", scenario]
    app.launch()
    return app
  }

  private func openLibrary(_ app: XCUIApplication) {
    XCTAssertTrue(app.openLibrary(), "The Library destination is unavailable")
  }

  private func selectCraft(_ title: String, in app: XCUIApplication) {
    XCTAssertTrue(app.openCraft(title), "\(title) is unavailable")
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
    selectCraft("Coloring", in: app)
    openCard(named: "Garden Friends", in: app)
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

  private func replaceText(in field: XCUIElement, with value: String, app: XCUIApplication) {
    field.tap()
    field.press(forDuration: 1.1)
    let selectAll = app.menuItems["Select All"].firstMatch
    XCTAssertTrue(selectAll.waitForExistence(timeout: 3))
    selectAll.tap()
    field.typeText(value)
    XCTAssertEqual(field.value as? String, value)
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
