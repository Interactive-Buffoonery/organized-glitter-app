import XCTest

@MainActor
final class AccountDeletionUITests: XCTestCase {
  func testDeletionRequiresFreshAuthThenExplicitFinalConfirmation() {
    let app = launchFixture(reset: true)
    openDeletion(app)
    let password = app.secureTextFields["deletion.password"]
    XCTAssertTrue(password.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Verify with Google"].exists)
    XCTAssertFalse(app.buttons["Verify with Discord"].exists)
    XCTAssertFalse(app.buttons["Continue with Apple"].exists)
    XCTAssertFalse(app.buttons["deletion.review"].exists)
    password.tap()
    password.typeText("fictional")
    app.buttons["deletion.verifyPassword"].tap()
    let review = app.buttons["deletion.review"]
    XCTAssertTrue(review.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["deletion.ready"].exists)
    review.tap()
    XCTAssertTrue(app.buttons["Delete Account Permanently"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(review.exists)
    review.tap()
    app.buttons["Delete Account Permanently"].tap()
    XCTAssertTrue(app.staticTexts["deletion.completed"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Vendor cleanup is pending."].exists)
    app.buttons["deletion.done"].tap()
    XCTAssertTrue(app.buttons["welcomeSignIn"].waitForExistence(timeout: 5))
  }

  func testUncertainDeletionRecoversBeforeLoginAfterRelaunch() {
    let app = launchFixture(reset: true, uncertain: true)
    openDeletion(app)
    let password = app.secureTextFields["deletion.password"]
    XCTAssertTrue(password.waitForExistence(timeout: 5))
    password.tap(); password.typeText("fictional")
    app.buttons["deletion.verifyPassword"].tap()
    XCTAssertTrue(app.buttons["deletion.review"].waitForExistence(timeout: 5))
    app.buttons["deletion.review"].tap()
    app.buttons["Delete Account Permanently"].tap()
    XCTAssertTrue(app.buttons["deletion.retry"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["deletion.uncertain"].exists)
    app.terminate()
    app.launchArguments = ["-ui-testing-authenticated", "-overview-fixture", "design", "-fixture-deletion"]
    app.launch()
    XCTAssertTrue(app.buttons["deletion.retry"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["account.open"].exists)
    app.buttons["deletion.retry"].tap()
    XCTAssertTrue(app.staticTexts["deletion.completed"].waitForExistence(timeout: 10))
    app.buttons["deletion.done"].tap()
  }

  private func launchFixture(reset: Bool, uncertain: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-authenticated", "-overview-fixture", "design", "-fixture-deletion"]
    if reset { app.launchArguments += ["-fixture-deletion-reset"] }
    if uncertain { app.launchArguments += ["-fixture-deletion-uncertain"] }
    app.launch()
    return app
  }

  private func openDeletion(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["account.open"].waitForExistence(timeout: 10))
    app.buttons["account.open"].tap()
    let entry = app.buttons["account.delete"]
    for _ in 0..<10 {
      if entry.exists && entry.isHittable { break }
      app.collectionViews.firstMatch.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(entry.isHittable)
    entry.tap()
  }
}
