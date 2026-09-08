import XCTest

@MainActor
final class NumberSectionPickerUITests: XCTestCase {
  func testNumberEntryValidationAndReroll() {
    let app = XCUIApplication()
    app.launchArguments.append("-ui-testing-authenticated")
    app.launch()
    openRandomizer(app)

    let pick = app.buttons["Pick number"]
    XCTAssertTrue(pick.waitForExistence(timeout: 5))
    pick.tap()
    XCTAssertTrue(app.staticTexts[
      "Enter whole numbers greater than zero, separated by commas."
    ].waitForExistence(timeout: 3))

    let field = app.descendants(matching: .any)["numberSectionInput"]
    XCTAssertTrue(field.exists)
    field.tap()
    field.typeText("8, 8")
    pick.tap()

    let result = app.staticTexts["Number picked, 8"]
    XCTAssertTrue(result.waitForExistence(timeout: 3))
    for _ in 0..<3 {
      app.buttons["Try again"].tap()
      XCTAssertTrue(result.exists)
    }
    XCTAssertTrue(app.staticTexts[
      "Picks stay on this screen and are not saved to a project."
    ].exists)
    capture("number-picker-result")
  }

  func testLargestTextKeepsPickActionReachable() {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ui-testing-authenticated", "-UIPreferredContentSizeCategoryName",
      "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    openRandomizer(app)
    let pick = app.buttons["Pick number"]
    XCTAssertTrue(pick.waitForExistence(timeout: 5))
    if !pick.isHittable { app.swipeUp() }
    XCTAssertTrue(pick.isHittable)
    capture("number-picker-largest-text")
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func openRandomizer(_ app: XCUIApplication) {
    let tab = app.buttons["Randomizer"].firstMatch
    if app.buttons["Next Page"].exists {
      app.buttons["Next Page"].tap()
    }
    XCTAssertTrue(tab.waitForExistence(timeout: 5))
    tab.tap()
  }
}
