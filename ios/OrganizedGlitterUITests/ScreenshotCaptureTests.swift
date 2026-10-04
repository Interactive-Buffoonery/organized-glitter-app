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

    for label in ["Home", "Library", "Notes", "Search"] {
      let tab = app.buttons[label].firstMatch
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

  func testCaptureKarlaTypography() throws {
    guard let dir = ProcessInfo.processInfo.environment["KARLA_SCREENSHOT_DIR"] else {
      throw XCTSkip("Typography capture is opt-in; set KARLA_SCREENSHOT_DIR.")
    }
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let appearance = ProcessInfo.processInfo.environment["KARLA_APPEARANCE"] ?? "light"
    for (size, category) in [
      ("default", "UICTContentSizeCategoryL"),
      ("ax3", "UICTContentSizeCategoryAccessibilityXL"),
    ] {
      let prefix = "\(dir)/\(appearance)-\(size)"
      let app = XCUIApplication()
      let typographyArguments = [
        "-selectedThemeFlavor", "system",
        "-UIPreferredContentSizeCategoryName", category,
      ]
      app.launchArguments = typographyArguments + [
        "-ui-testing-authenticated", "-overview-fixture", "design",
      ]
      app.launch()
      XCTAssertTrue(app.buttons["account.open"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.buttons.matching(
        NSPredicate(format: "label CONTAINS %@", "Passionflowers")).firstMatch
        .waitForExistence(timeout: 10))
      try save(app.screenshot(), to: "\(prefix)-home.png")
      app.swipeUp()
      try save(app.screenshot(), to: "\(prefix)-home-lower.png")

      app.buttons["account.open"].tap()
      XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
      try save(app.screenshot(), to: "\(prefix)-account.png")
      app.swipeUp()
      try save(app.screenshot(), to: "\(prefix)-account-lower.png")
      app.navigationBars["Account"].buttons["Done"].tap()

      XCTAssertTrue(app.openLibrary())
      let card = app.buttons.matching(
        NSPredicate(format: "label CONTAINS %@", "Summer Garden Blooms")).firstMatch
      XCTAssertTrue(card.waitForExistence(timeout: 10))
      try save(app.screenshot(), to: "\(prefix)-library.png")
      card.tap()
      XCTAssertTrue(app.buttons["detail.title"].waitForExistence(timeout: 5))
      try save(app.screenshot(), to: "\(prefix)-detail.png")
      app.swipeUp()
      try save(app.screenshot(), to: "\(prefix)-detail-lower.png")
      app.terminate()

      app.launchArguments = typographyArguments + [
        "-ui-testing-signed-out", "-ui-testing-social-providers",
      ]
      app.launch()
      XCTAssertTrue(app.buttons["welcomeSignIn"].waitForExistence(timeout: 5))
      try save(app.screenshot(), to: "\(prefix)-welcome.png")
      app.buttons["welcomeSignIn"].tap()
      let email = app.buttons["continueWithEmail"]
      XCTAssertTrue(email.waitForExistence(timeout: 5))
      try save(app.screenshot(), to: "\(prefix)-signin-methods.png")
      if !email.isHittable { app.swipeUp() }
      email.tap()
      XCTAssertTrue(app.buttons["signInButton"].waitForExistence(timeout: 5))
      try save(app.screenshot(), to: "\(prefix)-signin.png")
      app.swipeUp()
      try save(app.screenshot(), to: "\(prefix)-signin-lower.png")
      app.terminate()
    }
  }

  /// Library density on iPad: every view mode in portrait and landscape. Set
  /// the simulator appearance from the host and pass it as
  /// `LIBRARY_DENSITY_APPEARANCE` to name the files.
  func testCaptureLibraryDensity() throws {
    guard let dir = ProcessInfo.processInfo.environment["LIBRARY_DENSITY_DIR"] else {
      throw XCTSkip("Library density capture is opt-in; set LIBRARY_DENSITY_DIR.")
    }
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let appearance = ProcessInfo.processInfo.environment["LIBRARY_DENSITY_APPEARANCE"] ?? "light"
    let app = XCUIApplication()
    app.launchArguments = [
      "-selectedThemeFlavor", "system", "-ui-testing-authenticated", "-overview-fixture", "design",
    ]
    XCUIDevice.shared.orientation = .portrait
    app.launch()
    XCTAssertTrue(app.openLibrary())
    let modes = app.segmentedControls["library.viewMode"]
    XCTAssertTrue(modes.waitForExistence(timeout: 10))
    for (orientation, name) in [
      (UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape"),
    ] {
      XCUIDevice.shared.orientation = orientation
      Thread.sleep(forTimeInterval: 2)
      for mode in ["Covers", "Compact", "List"] {
        modes.buttons[mode].tap()
        Thread.sleep(forTimeInterval: 1.5)
        try save(XCUIScreen.main.screenshot(), to: "\(dir)/\(name)-\(appearance)-\(mode.lowercased()).png")
      }
    }
    modes.buttons["Covers"].tap()
    let sidebarToggle = app.buttons.matching(
      NSPredicate(format: "label CONTAINS[c] %@", "sidebar")).allElementsBoundByIndex
      .first { $0.isHittable }
    if let sidebarToggle {
      sidebarToggle.tap()
      Thread.sleep(forTimeInterval: 1.5)
      try save(XCUIScreen.main.screenshot(), to: "\(dir)/landscape-collapsed-\(appearance)-covers.png")
      sidebarToggle.tap()
    }
    XCUIDevice.shared.orientation = .portrait
    app.terminate()

    let baseArguments = app.launchArguments + ["-fixture-long-library-text"]
    for (size, category) in [
      ("ax1", "UICTContentSizeCategoryAccessibilityM"),
      ("ax3", "UICTContentSizeCategoryAccessibilityXL"),
      ("ax5", "UICTContentSizeCategoryAccessibilityXXXL"),
    ] {
      app.launchArguments = baseArguments + ["-UIPreferredContentSizeCategoryName", category]
      app.launch()
      XCTAssertTrue(app.openLibrary())
      XCTAssertTrue(modes.waitForExistence(timeout: 10))
      for (orientation, name) in [
        (UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape"),
      ] {
        XCUIDevice.shared.orientation = orientation
        for mode in ["Covers", "Compact", "List"] {
          modes.buttons[mode].tap()
          XCTAssertTrue(modes.buttons[mode].isSelected)
          try save(XCUIScreen.main.screenshot(), to: "\(dir)/\(name)-\(size)-\(appearance)-\(mode.lowercased()).png")
        }
      }
      app.terminate()
    }
    XCUIDevice.shared.orientation = .portrait
  }

  private func captureAccountEntry(into dir: String) throws {
    let signedOut = XCUIApplication()
    signedOut.launchArguments += ["-ui-testing-signed-out", "-ui-testing-social-providers"]
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
