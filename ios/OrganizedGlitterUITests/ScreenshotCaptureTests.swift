import XCTest

/// Opt-in capture helper, not a test of behavior. Run with
/// `TEST_RUNNER_SCREENSHOT_DIR=/tmp/og-shots xcodebuild test ...`; set the
/// simulator appearance from the host (`xcrun simctl ui <udid> appearance`)
/// before each run to capture a variant.
@MainActor
final class ScreenshotCaptureTests: XCTestCase {
  func testCaptureScreens() throws {
    guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else {
      throw XCTSkip("Screenshot capture is opt-in; set SCREENSHOT_DIR.")
    }
    try FileManager.default.createDirectory(
      atPath: dir, withIntermediateDirectories: true)

    let app = XCUIApplication()
    app.launchArguments.append("-ui-testing-authenticated")
    app.launch()

    for label in ["Overview", "Library", "Create", "Account"] {
      let tab = app.tabBars.buttons[label]
      guard tab.waitForExistence(timeout: 3) else {
        // iPad may present destinations outside a compact tab bar.
        continue
      }
      tab.tap()
      Thread.sleep(forTimeInterval: 1)
      try save(app.screenshot(), to: "\(dir)/\(label.lowercased()).png")
    }

    app.terminate()
    try captureAccountEntry(into: dir)
  }

  func testCaptureAccountEntry() throws {
    guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else {
      throw XCTSkip("Screenshot capture is opt-in; set SCREENSHOT_DIR.")
    }
    try FileManager.default.createDirectory(
      atPath: dir, withIntermediateDirectories: true)
    try captureAccountEntry(into: dir)
  }

  private func captureAccountEntry(into dir: String) throws {
    let signedOut = XCUIApplication()
    signedOut.launchArguments.append("-ui-testing-signed-out")
    signedOut.launch()
    XCTAssertTrue(signedOut.buttons["welcomeSignIn"].waitForExistence(timeout: 5))
    try save(signedOut.screenshot(), to: "\(dir)/welcome.png")

    signedOut.buttons["welcomeCreateAccount"].tap()
    XCTAssertTrue(signedOut.buttons["continueWithEmail"].waitForExistence(timeout: 5))
    try save(signedOut.screenshot(), to: "\(dir)/register-methods.png")
    signedOut.buttons["continueWithEmail"].tap()
    XCTAssertTrue(signedOut.buttons["createAccountButton"].waitForExistence(timeout: 5))
    dismissKeyboard(in: signedOut)
    try save(signedOut.screenshot(), to: "\(dir)/register.png")
    signedOut.navigationBars.buttons.element(boundBy: 0).tap()
    signedOut.navigationBars.buttons.element(boundBy: 0).tap()

    signedOut.buttons["welcomeSignIn"].tap()
    XCTAssertTrue(signedOut.buttons["continueWithEmail"].waitForExistence(timeout: 5))
    try save(signedOut.screenshot(), to: "\(dir)/signin-methods.png")
    signedOut.buttons["continueWithEmail"].tap()
    XCTAssertTrue(signedOut.buttons["signInButton"].waitForExistence(timeout: 5))
    dismissKeyboard(in: signedOut)
    try save(signedOut.screenshot(), to: "\(dir)/signin.png")

    signedOut.buttons["Reset a forgotten password"].tap()
    XCTAssertTrue(signedOut.buttons["passwordResetSend"].waitForExistence(timeout: 5))
    dismissKeyboard(in: signedOut)
    try save(signedOut.screenshot(), to: "\(dir)/password-reset.png")
  }

  private func dismissKeyboard(in app: XCUIApplication) {
    if app.keyboards.element.waitForExistence(timeout: 1) {
      app.keyboards.buttons["Return"].tap()
      if app.keyboards.element.exists {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
      }
      Thread.sleep(forTimeInterval: 0.5)
    }
  }

  private func save(_ screenshot: XCUIScreenshot, to path: String) throws {
    try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
  }
}
