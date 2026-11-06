import Photos
import XCTest
@testable import OrganizedGlitter

@MainActor
final class CameraRollSaveTests: XCTestCase {
  func testPreferenceDefaultsOnAndPersistsChoice() throws {
    let name = "CameraRollSaveTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    XCTAssertTrue(CameraPhotoPreference.isEnabled(in: defaults))
    defaults.set(false, forKey: CameraPhotoPreference.key)
    XCTAssertFalse(CameraPhotoPreference.isEnabled(in: defaults))
    defaults.set(true, forKey: CameraPhotoPreference.key)
    XCTAssertTrue(CameraPhotoPreference.isEnabled(in: defaults))
  }

  func testDisabledSkipsPermissionAndSave() async {
    var requested = false
    var saved = false
    await CameraRollSave.save(enabled: false) {
      requested = true
      return .authorized
    } createAsset: {
      saved = true
    }
    XCTAssertFalse(requested)
    XCTAssertFalse(saved)
  }

  func testOnlyAuthorizedAccessSaves() async {
    for status in [PHAuthorizationStatus.authorized, .denied, .restricted, .notDetermined, .limited] {
      var saves = 0
      await CameraRollSave.save(enabled: true) { status } createAsset: { saves += 1 }
      XCTAssertEqual(saves, status == .authorized ? 1 : 0)
    }
  }

  func testSaveFailureIsNonFatal() async {
    struct SaveError: Error {}
    var attempts = 0
    await CameraRollSave.save(enabled: true) { .authorized } createAsset: {
      attempts += 1
      throw SaveError()
    }
    XCTAssertEqual(attempts, 1)
  }
}
