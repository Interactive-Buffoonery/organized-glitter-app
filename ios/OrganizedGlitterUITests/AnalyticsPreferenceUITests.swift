import XCTest

@MainActor
final class AnalyticsPreferenceUITests: XCTestCase {
  func testAnalyticsPreferencePersistsAcrossRelaunch() {
    let app = launchFixture()
    let toggle = openPrivacy(app)
    let initialValue = toggle.value as? String
    XCTAssertNotNil(initialValue)
    toggleControl(toggle).tap()
    let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", initialValue ?? ""), object: toggle)
    XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    let changedValue = toggle.value as? String
    XCTAssertNotEqual(changedValue, initialValue)
    app.terminate()
    app.launch()
    let restored = openPrivacy(app)
    XCTAssertEqual(restored.value as? String, changedValue)
    toggleControl(restored).tap()
    let reset = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", initialValue ?? ""), object: restored)
    XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 5), .completed)
    XCTAssertEqual(restored.value as? String, initialValue)
  }

  func testPrivacyPreferenceIsReachableAtLargestDynamicType() {
    let app = launchFixture(largeText: true)
    let toggle = openPrivacy(app)
    XCTAssertTrue(toggleControl(toggle).isHittable)
    XCTAssertEqual(toggle.label, "Share usage analytics")
    let disclosure = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "Turning this off stops new collection on this device")
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

  private func launchFixture(largeText: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-authenticated", "-overview-fixture", "design"]
    if largeText {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    }
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
