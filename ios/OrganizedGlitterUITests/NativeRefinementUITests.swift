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
    XCTAssertTrue(app.staticTexts["Summer Garden Blooms"].waitForExistence(timeout: 5))
    try capture("refinement-02-diamond-gallery")

    openCard(named: "Summer Garden Blooms", in: app)
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    assertArtworkLoaded("Project artwork", in: app)
    try capture("refinement-03-diamond-detail")

    app.navigationBars.buttons.element(boundBy: 0).tap()
    selectCraft("Coloring", in: app)
    XCTAssertTrue(app.staticTexts["Smithsonian Libraries Coloring Pages, Volume 2"].waitForExistence(timeout: 5))
    try capture("refinement-04-book-gallery")

    openCard(named: "Smithsonian Libraries Coloring Pages, Volume 2", in: app)
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
    openCard(named: "Summer Garden Blooms", in: app)
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))

    button("detail.edit", in: app).tap()
    XCTAssertTrue(app.navigationBars["Edit Project"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Summer Garden Blooms"].exists)

    button("detail.edit", in: app).tap()
    let title = app.textFields["Title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    replaceText(in: title, with: "Summer Garden Blooms updated", app: app)
    app.buttons["Save"].tap()
    XCTAssertTrue(element("detail.diamond", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Summer Garden Blooms updated"].waitForExistence(timeout: 5))

    button("detail.more", in: app).tap()
    button("detail.delete", in: app).tap()
    let confirmation = confirmationButton(named: "Delete Project", in: app)
    XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
    confirmation.tap()
    XCTAssertTrue(element("detail.diamond", in: app).waitForNonExistence(timeout: 5))
    XCTAssertTrue(
      app.navigationBars["Library"].waitForExistence(timeout: 5)
        || app.navigationBars["Diamond art"].exists)
    XCTAssertFalse(app.staticTexts["Summer Garden Blooms updated"].exists)
  }

  func testDiamondDetailShowsSpecsDetailsAndChangesStatus() throws {
    let app = launchFixture()
    openLibrary(app)
    openCard(named: "Summer Garden Blooms", in: app)
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
      app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Bright summer blooms"))
        .firstMatch.exists)
    try capture("detail-diamond-lower")
  }

  func testPhotoViewerOpensCoverAndPagesProgressPhotos() {
    let app = launchFixture()
    openLibrary(app)
    openCard(named: "Summer Garden Blooms", in: app)
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
    // The out-of-process picker reports its cells as not hittable.
    photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
    // The out-of-process picker reports its cells as not hittable.
    photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(element("photoViewer.image", in: app).waitForExistence(timeout: 5))
    button("photoViewer.close", in: app).tap()
    XCTAssertTrue(element("detail.page", in: app).exists)
  }

  func testBookPagesPaginateAndNavigateToTheNextPage() {
    let app = launchFixture(scenario: "many-pages")
    openLibrary(app)
    selectCraft("Coloring", in: app)
    openCard(named: "Smithsonian Libraries Coloring Pages, Volume 2", in: app)
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
      NSPredicate(format: "label == %@", "Page photo 2: Passionflowers")
    ).firstMatch
    XCTAssertTrue(uploadedPhoto.waitForExistence(timeout: 10))
    XCTAssertTrue(element("detail.page", in: app).exists)
  }

  func testColorKeysSetUpEnterAndAddSymbols() throws {
    let app = launchFixture()
    openFirstDesignPage(in: app)

    let setUp = button("colorKeys.setup", in: app)
    XCTAssertTrue(setUp.waitForExistence(timeout: 5))
    makeHittable(setUp, in: app)
    try capture("colorkeys-01-empty")
    setUp.tap()

    let z = element("colorKeys.setup.u:007A", in: app)
    XCTAssertTrue(z.waitForExistence(timeout: 5))
    XCTAssertEqual(z.label, "Lowercase z")
    for letter in ["007A", "0079", "0078"] { element("colorKeys.setup.u:\(letter)", in: app).tap() }
    try capture("colorkeys-02-setup")
    button("colorKeys.setup.save", in: app).tap()

    let first = button("colorKeys.row.0", in: app)
    XCTAssertTrue(first.waitForExistence(timeout: 10))
    XCTAssertTrue(button("colorKeys.row.32", in: app).exists)
    XCTAssertFalse(button("colorKeys.row.33", in: app).exists)
    XCTAssertTrue(first.label.hasPrefix("One, No code yet"))
    first.tap()

    let code = app.textFields["colorKeys.entry.code"]
    XCTAssertTrue(code.waitForExistence(timeout: 5))
    code.tap()
    code.typeText("B000")
    let name = app.textFields["colorKeys.entry.colorName"]
    name.tap()
    name.typeText("Pale porcelain")
    try capture("colorkeys-03-entry")
    let saveNext = button("colorKeys.entry.saveNext", in: app)
    makeHittable(saveNext, in: app)
    saveNext.tap()

    XCTAssertTrue(app.navigationBars["Edit color"].waitForExistence(timeout: 5))
    let nextCode = app.textFields["colorKeys.entry.code"]
    XCTAssertEqual(nextCode.value as? String, "Code")
    nextCode.tap()
    nextCode.typeText("B0")
    let suggestion = app.buttons["Use B000 Pale porcelain"]
    XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
    suggestion.tap()
    XCTAssertEqual(app.textFields["colorKeys.entry.colorName"].value as? String, "Pale porcelain")
    button("colorKeys.entry.save", in: app).tap()

    XCTAssertTrue(first.waitForExistence(timeout: 5))
    XCTAssertTrue(first.label.hasPrefix("One, B000, Pale porcelain"))
    XCTAssertTrue(button("colorKeys.row.1", in: app).label.hasPrefix("Two, B000"))

    button("colorKeys.add", in: app).tap()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    search.typeText("trident")
    XCTAssertTrue(element("symbolPicker.footer", in: app).waitForExistence(timeout: 5))
    try capture("colorkeys-04-picker")
    let psi = button("symbolPicker.u:03C8", in: app)
    XCTAssertTrue(psi.waitForExistence(timeout: 5))
    XCTAssertEqual(psi.label, "Psi")
    psi.tap()
    XCTAssertTrue(app.navigationBars["Add color"].waitForExistence(timeout: 5))
    button("colorKeys.entry.save", in: app).tap()

    let added = button("colorKeys.row.33", in: app)
    XCTAssertTrue(added.waitForExistence(timeout: 5))
    XCTAssertTrue(added.label.hasPrefix("Psi, No code yet"))
    try capture("colorkeys-05-rows")
  }

  func testColorKeysReorderInPanel() throws {
    let app = launchFixture()
    openFirstDesignPage(in: app)

    let setUp = button("colorKeys.setup", in: app)
    XCTAssertTrue(setUp.waitForExistence(timeout: 5))
    makeHittable(setUp, in: app)
    setUp.tap()
    button("colorKeys.setup.save", in: app).tap()
    XCTAssertTrue(button("colorKeys.row.0", in: app).waitForExistence(timeout: 10))

    let reorder = button("colorKeys.reorder", in: app)
    makeHittable(reorder, in: app)
    reorder.tap()
    XCTAssertTrue(app.navigationBars["Sort Color Order"].waitForExistence(timeout: 5))
    let rows = app.cells
    XCTAssertTrue(rows.element(boundBy: 1).waitForExistence(timeout: 5))
    try capture("colorkeys-09-reorder")

    let handle = rows.element(boundBy: 1).buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Reorder")).firstMatch
    XCTAssertTrue(handle.exists)
    handle.press(forDuration: 0.6, thenDragTo: rows.element(boundBy: 0))
    let firstInPanel = rows.element(boundBy: 0).otherElements.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "colorKeys.reorder.")).firstMatch
    XCTAssertTrue(firstInPanel.label.hasPrefix("Two"))
    button("colorKeys.reorder.done", in: app).tap()

    XCTAssertTrue(app.navigationBars["Sort Color Order"].waitForNonExistence(timeout: 5))
    let first = button("colorKeys.row.0", in: app)
    let moved = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label BEGINSWITH %@", "Two"), object: first)
    XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 10), .completed)
    XCTAssertTrue(button("colorKeys.row.1", in: app).label.hasPrefix("One"))
  }

  func testColorKeysSendSymbolPhoto() throws {
    let app = launchFixture()
    openFirstDesignPage(in: app)

    let addFirst = button("colorKeys.addFirst", in: app)
    XCTAssertTrue(addFirst.waitForExistence(timeout: 5))
    makeHittable(addFirst, in: app)
    addFirst.tap()
    let footer = button("symbolPicker.footer", in: app)
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    for _ in 0..<30 where !(footer.exists && footer.isHittable) { app.swipeUp() }
    footer.tap()

    XCTAssertTrue(app.navigationBars["Send a symbol"].waitForExistence(timeout: 5))
    XCTAssertTrue((app.textFields["symbolRequest.bookLabel"].value as? String ?? "").contains("· Page"))
    XCTAssertFalse(button("symbolRequest.send", in: app).isEnabled)
    button("symbolRequest.choosePhoto", in: app).tap()
    // The system picker shows the simulator's sample library; any photo will do.
    let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 10))
    // The out-of-process picker reports its cells as not hittable.
    photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(app.images["Symbol photo"].waitForExistence(timeout: 15))
    let description = app.textFields["symbolRequest.description"]
    description.tap()
    description.typeText("Two w’s stacked")
    let email = app.textFields["symbolRequest.email"]
    if (email.value as? String ?? "").contains("@") == false {
      makeHittable(email, in: app)
      email.tap()
      email.typeText("crafter@example.com")
    }
    try capture("colorkeys-06-request")
    button("symbolRequest.send", in: app).tap()

    XCTAssertTrue(app.navigationBars["Add color"].waitForExistence(timeout: 10))
    try capture("colorkeys-07-request-entry")
    button("colorKeys.entry.save", in: app).tap()
    let row = button("colorKeys.row.0", in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    XCTAssertTrue(row.label.hasPrefix("Requested symbol, No code yet"))
    for _ in 0..<8 where !row.isHittable { app.swipeDown() }
    try capture("colorkeys-08-request-row")
  }

  func testColorKeysAtLargestTextSize() throws {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ui-testing-authenticated", "-overview-fixture", "design",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    openFirstDesignPage(in: app)

    let setUp = button("colorKeys.setup", in: app)
    XCTAssertTrue(setUp.waitForExistence(timeout: 5))
    makeHittable(setUp, in: app)
    setUp.tap()
    let save = button("colorKeys.setup.save", in: app)
    XCTAssertTrue(save.waitForExistence(timeout: 5))
    try capture("colorkeys-ax5-setup")
    save.tap()

    let copy = button("colorKeys.copy", in: app)
    XCTAssertTrue(copy.waitForExistence(timeout: 10))
    for _ in 0..<12 where !copy.isHittable { app.swipeDown() }
    XCTAssertTrue(copy.isHittable)
    try capture("colorkeys-ax5-rows")
    let first = button("colorKeys.row.0", in: app)
    makeHittable(first, in: app)
    first.tap()
    XCTAssertTrue(app.textFields["colorKeys.entry.code"].waitForExistence(timeout: 5))
    try capture("colorkeys-ax5-entry")
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
    openCard(named: "Smithsonian Libraries Coloring Pages, Volume 2", in: app)
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
