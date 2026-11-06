import XCTest

@MainActor
final class CameraPhotoSettingUITests: XCTestCase {
  func testCameraPhotoSettingAtLargestDynamicType() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing-authenticated", "-overview-fixture", "design",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    XCTAssertTrue(app.buttons["account.open"].waitForExistence(timeout: 10))
    app.buttons["account.open"].tap()
    let setting = app.switches["account.saveCameraPhotos"]
    for _ in 0..<16 {
      if setting.exists && setting.isHittable { break }
      app.scrollViews["account.list"].swipeUp(velocity: .slow)
    }
    XCTAssertTrue(setting.isHittable)
    XCTAssertEqual(setting.label, "Save photos taken in the app to the camera roll")
    let control = setting.switches.firstMatch.exists ? setting.switches.firstMatch : setting
    let original = control.value as? String
    control.tap()
    XCTAssertNotEqual(control.value as? String, original)
    control.tap()
    XCTAssertEqual(control.value as? String, original)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Camera photo setting at largest Dynamic Type"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
