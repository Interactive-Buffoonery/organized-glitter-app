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
    XCTAssertFalse(app.buttons["Continue with Apple to verify this account"].exists)
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

  func testUnavailableOnlyProviderOffersSupportDespiteGlobalPassword() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing-authenticated", "-overview-fixture", "design", "-fixture-deletion",
      "-fixture-deletion-reset", "-fixture-deletion-apple-only-unavailable",
    ]
    app.launch()
    openDeletion(app)

    let appleUnavailable = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Apple verification is unavailable now.")
    ).firstMatch
    XCTAssertTrue(appleUnavailable.waitForExistence(timeout: 5))
    XCTAssertTrue(app.secureTextFields["deletion.password"].exists)
    XCTAssertTrue(app.staticTexts["If this account has a password, you can try it here."].exists)
    XCTAssertFalse(app.buttons["Continue with Apple to verify this account"].exists)
    let support = app.descendants(matching: .any)["Contact support"]
    for _ in 0..<4 {
      if support.exists && support.isHittable { break }
      app.collectionViews.firstMatch.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(support.exists && support.isHittable)
    XCTAssertFalse(app.buttons["deletion.review"].exists)
  }

  func testCaptureAccountDeletionScreens() throws {
    guard let directory = ProcessInfo.processInfo.environment["ACCOUNT_DELETION_SCREENSHOT_DIR"] else {
      throw XCTSkip("Account deletion screenshots are opt-in.")
    }
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let app = XCUIApplication()
    app.launchArguments = [
      "-selectedThemeFlavor", "system", "-ui-testing-authenticated", "-overview-fixture", "design",
      "-fixture-deletion", "-fixture-deletion-reset", "-fixture-deletion-uncertain",
    ]
    app.launch()
    XCTAssertTrue(app.buttons["account.open"].waitForExistence(timeout: 10))
    app.buttons["account.open"].tap()
    let analytics = app.switches["account.usageAnalytics"]
    for _ in 0..<10 {
      if analytics.exists && analytics.isHittable { break }
      app.collectionViews.firstMatch.swipeUp(velocity: .slow)
    }
    try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(directory)/account-privacy.png"))
    let details = app.buttons["How analytics works"]
    if details.exists && details.isHittable {
      details.tap()
      try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(directory)/account-privacy-expanded.png"))
    }
    let entry = app.buttons["account.delete"]
    for _ in 0..<10 {
      if entry.exists && entry.isHittable { break }
      app.collectionViews.firstMatch.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(entry.isHittable)
    entry.tap()
    let password = app.secureTextFields["deletion.password"]
    XCTAssertTrue(password.waitForExistence(timeout: 5))
    try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(directory)/deletion-verification.png"))
    password.tap()
    password.typeText("fictional")
    app.buttons["deletion.verifyPassword"].tap()
    XCTAssertTrue(app.buttons["deletion.review"].waitForExistence(timeout: 5))
    try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(directory)/deletion-ready.png"))
    app.buttons["deletion.review"].tap()
    XCTAssertTrue(app.buttons["Delete Account Permanently"].waitForExistence(timeout: 5))
    try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(directory)/deletion-confirmation.png"))
    app.buttons["Delete Account Permanently"].tap()
    XCTAssertTrue(app.buttons["deletion.retry"].waitForExistence(timeout: 10))
    try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(directory)/deletion-recovery.png"))
    app.terminate()
    app.launchArguments.removeAll { $0 == "-fixture-deletion-reset" || $0 == "-fixture-deletion-uncertain" }
    app.launch()
    XCTAssertTrue(app.buttons["deletion.retry"].waitForExistence(timeout: 10))
    app.buttons["deletion.retry"].tap()
    XCTAssertTrue(app.staticTexts["deletion.completed"].waitForExistence(timeout: 10))
    try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(directory)/deletion-completed.png"))
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
