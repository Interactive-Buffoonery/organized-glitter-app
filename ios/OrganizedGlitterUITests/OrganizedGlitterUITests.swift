import XCTest

@MainActor
final class OrganizedGlitterUITests: XCTestCase {
  func testSignedOutAccountEntryPointsAreNative() {
    let app = XCUIApplication()
    app.launchArguments.append("-ui-testing-signed-out")
    app.launch()

    XCTAssertTrue(app.otherElements["welcomeWordmark"].waitForExistence(timeout: 2)
      || app.staticTexts["Organized Glitter"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["welcomeCreateAccount"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["welcomeSignIn"].exists)

    app.buttons["welcomeSignIn"].tap()
    XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["continueWithEmail"].exists)
    XCTAssertFalse(app.buttons["Continue with Apple"].exists)
    XCTAssertFalse(app.buttons["Continue with Google"].exists)
    XCTAssertFalse(app.buttons["Continue with Discord"].exists)

    app.buttons["continueWithEmail"].tap()
    XCTAssertTrue(app.staticTexts["Sign in with email"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["signInButton"].exists)
    XCTAssertTrue(app.buttons["Reset a forgotten password"].exists)
    XCTAssertTrue(app.buttons["Request a new verification email"].exists)

    app.buttons["signInButton"].tap()
    XCTAssertTrue(app.staticTexts["Error: Enter your email address and password."].waitForExistence(timeout: 2)
      || app.otherElements["signInError"].waitForExistence(timeout: 2)
      || app.staticTexts["Enter your email address and password."].waitForExistence(timeout: 2))

    app.buttons["Request a new verification email"].tap()
    XCTAssertTrue(app.staticTexts["Verify email"].waitForExistence(timeout: 2))
    app.navigationBars.buttons.element(boundBy: 0).tap()

    app.buttons["Reset a forgotten password"].tap()
    XCTAssertTrue(app.staticTexts["Reset password"].waitForExistence(timeout: 2))
    app.buttons["passwordResetBack"].tap()

    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()

    XCTAssertTrue(app.buttons["welcomeCreateAccount"].waitForExistence(timeout: 3))
    app.buttons["welcomeCreateAccount"].tap()
    XCTAssertTrue(app.otherElements["accountMethodTitle"].waitForExistence(timeout: 3)
      || app.staticTexts["Create account"].waitForExistence(timeout: 3))
    app.buttons["accountMethodSwitch"].tap()
    XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 3))
    app.buttons["accountMethodSwitch"].tap()
    XCTAssertTrue(app.staticTexts["Create account"].waitForExistence(timeout: 3))
    app.buttons["continueWithEmail"].tap()
    XCTAssertTrue(app.staticTexts["Create account with email"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["createAccountButton"].exists)
    let registrationSignIn = app.buttons["registrationSignIn"]
    if !registrationSignIn.exists {
      app.swipeUp()
    }
    XCTAssertTrue(registrationSignIn.waitForExistence(timeout: 3))
    registrationSignIn.tap()
    XCTAssertTrue(
      app.otherElements["accountMethodTitle"].waitForExistence(timeout: 3)
        || app.staticTexts["Welcome back"].waitForExistence(timeout: 3)
    )
  }

  func testAuthenticatedShellShowsFiveDestinations() {
    let app = XCUIApplication()
    app.launchArguments.append("-ui-testing-authenticated")
    app.launch()

    for label in ["Overview", "Library", "Create", "Randomizer", "Account"] {
      let destination = app.descendants(matching: .any)[label]
      XCTAssertTrue(destination.waitForExistence(timeout: 2), "\(label) is missing")
    }
  }

  func testSeededBackendLoadsOverviewAndLibrary() throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["RUN_SEEDED_POCKETBASE"] == "1" else {
      throw XCTSkip("Seeded PocketBase smoke is opt-in.")
    }
    let identity = try XCTUnwrap(environment["SEEDED_PB_IDENTITY"])
    let password = try XCTUnwrap(environment["SEEDED_PB_PASSWORD"])

    let app = XCUIApplication()
    app.launch()

    if app.buttons["welcomeSignIn"].waitForExistence(timeout: 2) {
      app.buttons["welcomeSignIn"].tap()
      app.buttons["continueWithEmail"].tap()
    }

    let identityField = app.textFields["signInEmail"]
    if identityField.waitForExistence(timeout: 2) {
      identityField.tap()
      identityField.typeText(identity)
      app.secureTextFields["signInPassword"].tap()
      app.secureTextFields["signInPassword"].typeText(password)
      app.buttons["signInButton"].tap()
    }

    let library = app.tabBars.buttons["Library"].firstMatch
    XCTAssertTrue(library.waitForExistence(timeout: 5))
    library.tap()
    XCTAssertTrue(app.staticTexts["Local Active Kit"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Couldn’t load your library"].exists)
  }

  func testSeededBackendCreatesEditsAndDeletesDiamondProject() throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["RUN_SEEDED_POCKETBASE"] == "1" else {
      throw XCTSkip("Seeded PocketBase writes are opt-in.")
    }
    let identity = try XCTUnwrap(environment["SEEDED_PB_IDENTITY"])
    let password = try XCTUnwrap(environment["SEEDED_PB_PASSWORD"])
    let app = XCUIApplication()
    app.launch()
    signInIfNeeded(app, identity: identity, password: password)

    let library = app.tabBars.buttons["Library"].firstMatch
    XCTAssertTrue(library.waitForExistence(timeout: 5))
    library.tap()
    let addProject = app.buttons["Add diamond painting project"]
    XCTAssertTrue(addProject.waitForExistence(timeout: 5))
    addProject.tap()

    var currentTitle = "Native UI integration \(UUID().uuidString.prefix(8))"
    let title = app.textFields["Title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    title.tap()
    title.typeText(currentTitle)
    app.buttons["Save"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["detail.diamond"].waitForExistence(timeout: 8))
    var needsCleanup = true
    defer {
      if needsCleanup {
        deleteProjectIfPresent(named: currentTitle, in: app)
      }
    }

    app.buttons.matching(identifier: "detail.edit").firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Edit Project"].waitForExistence(timeout: 5))
    let editedTitle = "\(currentTitle) edited"
    replaceText(in: app.textFields["Title"], with: editedTitle)
    currentTitle = editedTitle
    let status = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH[c] %@", "Status")
    ).firstMatch
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    status.tap()
    app.buttons["In progress"].tap()
    app.buttons["Save"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["detail.diamond"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts[currentTitle].waitForExistence(timeout: 5))

    deleteOpenProject(in: app)
    XCTAssertFalse(app.staticTexts[currentTitle].waitForExistence(timeout: 3))
    needsCleanup = false
  }

  private func signInIfNeeded(
    _ app: XCUIApplication,
    identity: String,
    password: String
  ) {
    if app.buttons["welcomeSignIn"].waitForExistence(timeout: 2) {
      app.buttons["welcomeSignIn"].tap()
      app.buttons["continueWithEmail"].tap()
    }
    let identityField = app.textFields["signInEmail"]
    if identityField.waitForExistence(timeout: 2) {
      identityField.tap()
      identityField.typeText(identity)
      let passwordField = app.secureTextFields["signInPassword"]
      passwordField.tap()
      passwordField.typeText(password)
      app.buttons["signInButton"].tap()
      let notNow = app.buttons["Not Now"].firstMatch
      if notNow.waitForExistence(timeout: 5) {
        notNow.tap()
      }
    }
    XCTAssertTrue(app.tabBars.buttons["Library"].firstMatch.waitForExistence(timeout: 8))
  }

  private func replaceText(in field: XCUIElement, with value: String) {
    field.tap()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(value)
    XCTAssertEqual(field.value as? String, value)
  }

  private func deleteOpenProject(in app: XCUIApplication) {
    app.buttons.matching(identifier: "detail.more").firstMatch.tap()
    app.buttons.matching(identifier: "detail.delete").firstMatch.tap()
    let sheetButton = app.sheets.buttons["Delete Project"]
    let confirmation = sheetButton.exists
      ? sheetButton : app.buttons.matching(identifier: "Delete Project").firstMatch
    if confirmation.waitForExistence(timeout: 2) {
      confirmation.tap()
    }
  }

  private func deleteProjectIfPresent(named title: String, in app: XCUIApplication) {
    app.activate()
    if app.descendants(matching: .any)["detail.diamond"].exists {
      deleteOpenProject(in: app)
      return
    }
    let library = app.tabBars.buttons["Library"]
    if library.exists {
      library.tap()
    }
    let search = app.textFields["library.search"]
    guard search.waitForExistence(timeout: 3) else { return }
    search.tap()
    search.typeText("\(title)\n")
    let card = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
    guard card.waitForExistence(timeout: 3) else { return }
    card.tap()
    guard app.descendants(matching: .any)["detail.diamond"].waitForExistence(timeout: 3) else {
      return
    }
    deleteOpenProject(in: app)
  }
}
