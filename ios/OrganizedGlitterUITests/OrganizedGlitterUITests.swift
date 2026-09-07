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

    app.buttons["welcomeCreateAccount"].tap()
    XCTAssertTrue(app.staticTexts["Create account"].waitForExistence(timeout: 2))
    app.buttons["continueWithEmail"].tap()
    XCTAssertTrue(app.staticTexts["Create account with email"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["createAccountButton"].exists)
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

    let library = app.descendants(matching: .any)["Library"]
    XCTAssertTrue(library.waitForExistence(timeout: 5))
    library.tap()
    XCTAssertTrue(app.staticTexts["Local Active Kit"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Couldn’t load your library"].exists)
  }
}
