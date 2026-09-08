# Overview D migration validation

Date: 2026-09-07. Starting checkout: clean `chore/native-ui-cleanup` at
`1a4080c`. No commit, push, or PR was created.

Design reference: `Interactive-Buffoonery/organized-glitter` revision
`0135e6d3caa73ea01224bda27c8e0abbb954fd19`, including the studio README,
current client source, and its linked standalone refinement. ADR 0001 retains
control of native palette/background values. See [design.md](design.md).

## Results

- Debug simulator builds passed for iPhone 17 and iPad Pro 11-inch (M5).
- Release simulator build passed, including compilation with debug fixtures excluded.
- All 61 Swift Testing tests passed, including craft filtering, artwork URL
  construction/missing filenames, clearing stale Library search on Wishlist
  navigation, and text contrast over the dark glow.
- The final iPhone UI run passed seven tests, including the existing shell and
  account-entry tests plus five Overview tests. One live PocketBase smoke test
  was skipped because seeded-backend testing was not enabled.
- iPad UI checks passed for active-work filtering/detail navigation,
  Wishlist routing, and loading/empty/error/retry states.
- Largest accessibility Dynamic Type was exercised on iPhone and iPad in
  portrait and landscape. The iPad accessibility craft-menu filter was also
  tapped and verified to remove diamond projects from the visible selection.
- System Reduce Motion was enabled and verified in Settings, then Overview
  and detail navigation were exercised. The test restores the prior setting.
  This check is opt-in for routine test runs.
- Live screenshots were inspected in both appearances. Artwork, missing-file
  and failed-image fallbacks, combined row labels, written status labels,
  scrolling, and iPad rotation were checked using fictional data.
- Matching fixed-position background samples before/after scrolling and visual
  inspection confirmed that content height does not move the dark glow.
  The scroll viewport owns the full-safe-area background; rows and the native
  tab bar do not replace it with an opaque page-sized layer.
- `git diff --check` passed.

Early UI runs failed because the first fixture did not establish a client
session and used the wrong settings collection name. Both fixture errors were
fixed and the affected tests passed on rerun. The initial Reduce Motion tap hit
the label region; targeting the switch and verifying its value resolved it.
Landscape app-cropped screenshots were malformed; full-screen captures replaced
them and were inspected. Those failed captures are not the selected evidence.

A final summary-label wording edit was followed by another successful Debug
build and simulator launch; it did not change loading or navigation behavior.

## Reproduce

All devices used iOS/iPadOS 26.5. Tests use the concrete client with an isolated
Debug-only URLProtocol fixture and dedicated fixture Keychain service. No live
backend is contacted by the fixture, including artwork requests. Artwork is a
fictional geometric illustration generated in memory; no customer or publisher
images are bundled. Normal application launches do not enable these fixtures.

From the repository root, the final combined test command was:

```sh
TEST_RUNNER_SCREENSHOT_DIR=/tmp/og-overview-shots/iphone-light \
TEST_RUNNER_RUN_SYSTEM_ACCESSIBILITY=1 \
xcodebuild \
  -project ios/OrganizedGlitter.xcodeproj \
  -scheme OrganizedGlitter \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/og-overview-build \
  -parallel-testing-enabled NO \
  test \
  -only-testing:OrganizedGlitterTests \
  -only-testing:OrganizedGlitterUITests/OverviewUITests \
  -only-testing:OrganizedGlitterUITests/OrganizedGlitterUITests
```

For iPad, the destination was `platform=iOS Simulator,name=OG Overview iPad`.
Appearance and Dynamic Type were set with `simctl ui` before the corresponding
runs. Accessibility rotation/menu checks used
`-only-testing:OrganizedGlitterUITests/OverviewUITests/testAccessibleLayoutAndRotation`.

To review manually, launch a Debug build with
`-ui-testing-authenticated -overview-fixture populated`. Substitute `loading`,
`empty`, or `error` for the other states. These flags are simulator review aids,
not production account or offline behavior.

## Selected screenshots

These are captures from this session's simulator runs, not substitutes for
runtime verification after future changes.

- [iPhone light](screenshots/overview-d/iphone-light.png)
- [iPhone dark](screenshots/overview-d/iphone-dark.png)
- [iPad light](screenshots/overview-d/ipad-light.png)
- [iPad dark](screenshots/overview-d/ipad-dark.png)
- [iPhone largest text](screenshots/overview-d/iphone-large.png)
- [iPad largest text, landscape](screenshots/overview-d/ipad-large-landscape.png)
- [iPad largest text, craft filter](screenshots/overview-d/ipad-large-filtered.png)

## Limits and next step

No live-backend, physical-device, spoken VoiceOver, or freeform iPad multitasking
window-resize test ran. Accessibility labels were inspected through XCTest;
iPad width changes were exercised by rotation. The existing per-craft limit of
five active records remains, with server totals shown separately. Private-file
release requirements remain those in the backend contract and architecture docs.

Native Notes has no functional destination yet. Wishlist currently routes to
the existing per-craft Library filters, not a combined Wishlist or link-saving
screen. Those unfinished features were not removed as dead code.

Library presentation and Wishlist handoff are recorded in
[Library validation](library-validation.md). The next smallest presentation
step is migrating Create's sticker chrome to the shared quiet treatment while
preserving its existing destinations. Notes should remain a separate,
explicitly scoped functional implementation.
