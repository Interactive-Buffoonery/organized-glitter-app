import XCTest

@MainActor
final class OrganizedGlitterUITests: XCTestCase {
  func testUncertainPasswordResetOffersSignInWithoutRetryingToken() {
    for scenario in ["reset-lost-connection", "reset-server-failure"] {
      let app = XCUIApplication()
      app.launchArguments += [
        "-ui-testing-signed-out", "-ui-testing-password-reset",
        "-overview-fixture", scenario,
      ]
      app.launch()

      let password = app.secureTextFields["passwordResetNewPassword"]
      XCTAssertTrue(password.waitForExistence(timeout: 5))
      password.tap()
      password.typeText("FixturePass1")
      let confirmation = app.secureTextFields["passwordResetNewPasswordConfirmation"]
      confirmation.tap()
      confirmation.typeText("FixturePass1")
      app.buttons["passwordResetConfirm"].tap()

      XCTAssertTrue(app.staticTexts["passwordResetOutcomeUnknown"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons["passwordResetTrySignIn"].exists)
      XCTAssertTrue(app.buttons["passwordResetRequestNewLink"].exists)
      XCTAssertFalse(app.buttons["passwordResetConfirm"].exists)
      XCTAssertFalse(app.staticTexts["passwordResetComplete"].exists)

      app.buttons["passwordResetTrySignIn"].tap()
      XCTAssertTrue(app.buttons["welcomeSignIn"].waitForExistence(timeout: 5))
      app.terminate()

      let relaunched = XCUIApplication()
      relaunched.launchArguments += ["-overview-fixture", scenario]
      relaunched.launch()
      XCTAssertTrue(relaunched.buttons["welcomeSignIn"].waitForExistence(timeout: 5))
      relaunched.terminate()
    }
  }

  func testRejectedResetLinkOffersNewEmail() {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ui-testing-signed-out", "-ui-testing-password-reset",
      "-overview-fixture", "reset-invalid-link",
    ]
    app.launch()
    let password = app.secureTextFields["passwordResetNewPassword"]
    XCTAssertTrue(password.waitForExistence(timeout: 5))
    password.tap()
    password.typeText("FixturePass1")
    let confirmation = app.secureTextFields["passwordResetNewPasswordConfirmation"]
    confirmation.tap()
    confirmation.typeText("FixturePass1")
    app.buttons["passwordResetConfirm"].tap()

    XCTAssertTrue(app.staticTexts["passwordResetInvalidLink"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.secureTextFields["passwordResetNewPassword"].exists)
    let request = app.buttons["passwordResetRequestNewLink"]
    XCTAssertEqual(request.label, "Send a new reset link")
    request.tap()
    let email = app.textFields["passwordResetEmail"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("fixture@example.test")
    app.buttons["passwordResetSend"].tap()
    XCTAssertTrue(app.staticTexts["passwordResetConfirmation"].waitForExistence(timeout: 5))
  }

  func testSignedInResetLinkShowsNoticeInsteadOfPasswordForm() {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ui-testing-authenticated", "-ui-testing-password-reset",
      "-overview-fixture", "populated",
    ]
    app.launch()
    let notice = app.alerts["You’re already signed in"]
    XCTAssertTrue(notice.waitForExistence(timeout: 5))
    XCTAssertFalse(app.secureTextFields["passwordResetNewPassword"].exists)
    notice.buttons["OK"].tap()
    XCTAssertFalse(app.buttons["welcomeSignIn"].exists)
  }

  func testRestoringExposesStatusAndHidesAccountActions() {
    let app = XCUIApplication()
    app.launchArguments.append("-ui-testing-restoring")
    app.launch()

    let status = app.staticTexts["launchProgress"]
    XCTAssertTrue(status.waitForExistence(timeout: 3))
    XCTAssertEqual(status.label, "Opening your library")
    XCTAssertTrue(app.descendants(matching: .any)["welcomeWordmark"].firstMatch.exists)
    XCTAssertFalse(app.buttons["welcomeCreateAccount"].exists)
    XCTAssertFalse(app.buttons["welcomeSignIn"].exists)
    XCTAssertFalse(app.buttons["welcomeUseSampleData"].exists)

    app.terminate()
    app.launchArguments = ["-ui-testing-signed-out"]
    app.launch()
    XCTAssertTrue(app.buttons["welcomeSignIn"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.staticTexts["launchProgress"].exists)
  }

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

  func testAuthenticatedShellShowsDestinationsAndToolbarActions() {
    let app = XCUIApplication()
    app.launchArguments.append("-ui-testing-authenticated")
    app.launch()

    for label in ["Home", "Library", "Search"] {
      let destination = app.descendants(matching: .any)[label]
      XCTAssertTrue(destination.waitForExistence(timeout: 2), "\(label) is missing")
    }
    XCTAssertFalse(app.tabBars.buttons["Create"].exists)
    XCTAssertFalse(app.tabBars.buttons["Randomizer"].exists)

    app.buttons["create.menu"].tap()
    XCTAssertTrue(app.buttons["create.diamond"].waitForExistence(timeout: 2))
    app.buttons["create.diamond"].tap()
    XCTAssertTrue(app.navigationBars.buttons["Cancel"].waitForExistence(timeout: 3))
    app.navigationBars.buttons["Cancel"].tap()

    app.buttons["account.open"].tap()
    XCTAssertTrue(app.staticTexts["Profile name"].waitForExistence(timeout: 3))
    app.buttons["Done"].tap()
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
    replaceText(in: app.textFields["Title"], with: editedTitle, app: app)
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

  private func replaceText(in field: XCUIElement, with value: String, app: XCUIApplication) {
    field.tap()
    field.press(forDuration: 1)
    let selectAll = app.menuItems["Select All"]
    XCTAssertTrue(selectAll.waitForExistence(timeout: 3))
    selectAll.tap()
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
    if app.buttons["Search"].firstMatch.exists {
      app.buttons["Search"].firstMatch.tap()
    }
    let search = app.searchFields.firstMatch
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
