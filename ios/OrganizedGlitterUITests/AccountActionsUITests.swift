import XCTest

@MainActor
final class AccountActionsUITests: XCTestCase {
  func testEmailRequestKeepsConfirmedAddress() {
    let app = launchAccount()
    let emailRow = app.buttons["account.changeEmail"]
    XCTAssertTrue(emailRow.waitForExistence(timeout: 5))
    emailRow.tap()
    let field = app.textFields["account.newEmail"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("new@example.test")
    app.buttons["account.sendEmailConfirmation"].tap()
    XCTAssertTrue(app.staticTexts["account.emailConfirmationSent"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts.containing(NSPredicate(
      format: "label CONTAINS %@", "Your email stays the same until you confirm")).firstMatch.exists)
    capture(app, name: "Change email confirmation")
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.staticTexts["fixture@example.test"].waitForExistence(timeout: 5))
  }

  func testPasswordChangeUsesNativeSecureFields() {
    let app = launchAccount()
    let row = app.buttons["account.changePassword"]
    reveal(row, in: app)
    row.tap()
    let current = app.secureTextFields["account.currentPassword"]
    XCTAssertTrue(current.waitForExistence(timeout: 5))
    current.tap()
    current.typeText("OldExample1")
    app.secureTextFields["account.newPassword"].tap()
    app.secureTextFields["account.newPassword"].typeText("NewExample2")
    app.secureTextFields["account.confirmPassword"].tap()
    app.secureTextFields["account.confirmPassword"].typeText("NewExample2")
    let save = app.buttons["account.savePassword"]
    reveal(save, in: app)
    save.tap()
    XCTAssertTrue(app.descendants(matching: .any)["account.passwordChanged"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.secureTextFields["account.currentPassword"].exists)
    capture(app, name: "Password changed")
  }

  func testEmailFormWorksAtLargestDynamicType() {
    let app = launchAccount(largeText: true)
    let row = app.buttons["account.changeEmail"]
    reveal(row, in: app)
    row.tap()
    XCTAssertTrue(app.textFields["account.newEmail"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["account.sendEmailConfirmation"].exists)
    capture(app, name: "Change email largest Dynamic Type")
  }

  func testEmailWriteIsDisabledOffline() {
    let app = launchAccount(offline: true)
    let row = app.buttons["account.changeEmail"]
    reveal(row, in: app)
    row.tap()
    let field = app.textFields["account.newEmail"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("new@example.test")
    XCTAssertFalse(app.buttons["account.sendEmailConfirmation"].isEnabled)
    capture(app, name: "Change email offline")
  }

  private func launchAccount(largeText: Bool = false, offline: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-authenticated", "-overview-fixture", "design"]
    if largeText {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    }
    if offline { app.launchArguments += ["-fixture-offline-after-account-load"] }
    app.launch()
    XCTAssertTrue(app.buttons["account.open"].waitForExistence(timeout: 10))
    app.buttons["account.open"].tap()
    return app
  }

  private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<8 {
      if element.exists && element.isHittable { return }
      app.collectionViews.firstMatch.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(element.isHittable)
  }

  private func capture(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
