import XCTest

@MainActor
final class AnalyticsPreferenceUITests: XCTestCase {
  func testAnalyticsPreferenceSavesToTheAccount() {
    let app = launchFixture()
    let toggle = openPrivacy(app)
    let initialValue = toggle.value as? String
    XCTAssertNotNil(initialValue)
    toggleControl(toggle).tap()
    let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", initialValue ?? ""), object: toggle)
    XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    let changedValue = toggle.value as? String
    XCTAssertNotEqual(changedValue, initialValue)
    let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", changedValue ?? ""), object: toggle)
    XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed)
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: toggle)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    toggleControl(toggle).tap()
    let reset = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", initialValue ?? ""), object: toggle)
    XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 5), .completed)
    XCTAssertEqual(toggle.value as? String, initialValue)
  }

  func testLocalPauseShowsSeparateStatusAndKeepsAccountChoice() {
    let app = launchFixture()
    let toggle = openPrivacy(app)
    let initialValue = toggle.value as? String
    let pause = app.buttons["account.pauseAnalytics"]
    for _ in 0..<4 {
      if pause.exists && pause.isHittable { break }
      app.collectionViews.firstMatch.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(pause.isHittable)
    pause.tap()
    XCTAssertTrue(app.staticTexts["account.analyticsPaused"].waitForExistence(timeout: 5))
    XCTAssertEqual(toggle.value as? String, initialValue)
  }

  func testOfflineLocalPauseIsAvailableWhileAccountWritesAreDisabled() {
    let app = launchFixture(offline: true)
    let toggle = openPrivacy(app)
    let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: toggle)
    XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 5), .completed)
    let pause = app.buttons["account.pauseAnalytics"]
    for _ in 0..<4 {
      if pause.exists && pause.isHittable { break }
      app.collectionViews.firstMatch.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(pause.isEnabled)
    pause.tap()
    XCTAssertTrue(app.staticTexts["account.analyticsPaused"].waitForExistence(timeout: 5))
    let resume = app.buttons["account.resumeAnalytics"]
    if resume.exists { XCTAssertFalse(resume.isEnabled) }
  }

  func testPrivacyPreferenceIsReachableAtLargestDynamicType() {
    let app = launchFixture(largeText: true)
    let toggle = openPrivacy(app)
    XCTAssertTrue(toggleControl(toggle).isHittable)
    XCTAssertEqual(toggle.label, "Share usage analytics")
    let disclosure = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "applies anywhere you sign in")
    ).firstMatch
    for _ in 0..<4 {
      if disclosure.exists { break }
      app.collectionViews.firstMatch.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(disclosure.exists)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Account analytics privacy at largest Dynamic Type"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func launchFixture(largeText: Bool = false, offline: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-authenticated", "-overview-fixture", "design"]
    if largeText {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    }
    if offline { app.launchArguments += ["-fixture-offline-after-account-load"] }
    app.launch()
    return app
  }

  private func openPrivacy(_ app: XCUIApplication) -> XCUIElement {
    XCTAssertTrue(app.buttons["account.open"].waitForExistence(timeout: 10))
    app.buttons["account.open"].tap()
    let list = app.collectionViews.firstMatch
    XCTAssertTrue(list.waitForExistence(timeout: 5))
    let toggle = app.switches["account.usageAnalytics"]
    for _ in 0..<8 {
      if toggle.exists && toggleControl(toggle).isHittable { return toggle }
      list.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(toggle.exists)
    XCTAssertTrue(toggleControl(toggle).isHittable)
    return toggle
  }

  private func toggleControl(_ element: XCUIElement) -> XCUIElement {
    let control = element.switches.firstMatch
    return control.exists ? control : element
  }
}
