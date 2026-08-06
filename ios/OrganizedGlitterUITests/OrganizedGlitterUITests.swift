import XCTest

@MainActor
final class OrganizedGlitterUITests: XCTestCase {
  func testSignedOutAccountEntryPointsAreNative() {
    let app = XCUIApplication()
    app.launchArguments.append("-ui-testing-signed-out")
    app.launch()

    XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["Create an Organized Glitter account"].exists)
    XCTAssertTrue(app.buttons["Reset a forgotten password"].exists)
    XCTAssertTrue(app.buttons["Request a new verification email"].exists)

    app.buttons["Create an Organized Glitter account"].tap()
    XCTAssertTrue(app.navigationBars["Create Account"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["Create Account"].exists)
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

    let identityField = app.textFields["Email address"]
    if identityField.waitForExistence(timeout: 2) {
      identityField.tap()
      identityField.typeText(identity)
      app.secureTextFields["Password"].tap()
      app.secureTextFields["Password"].typeText(password)
      app.buttons["Sign In"].tap()
    }

    let library = app.descendants(matching: .any)["Library"]
    XCTAssertTrue(library.waitForExistence(timeout: 5))
    library.tap()
    XCTAssertTrue(app.staticTexts["Local Active Kit"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Couldn’t load your library"].exists)
  }
}
