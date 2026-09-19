# Native refinement validation

The approved references are in `design-previews/native-refinement/`. They guide
composition; the five destinations, status vocabulary, record ownership, and
Berry Cream background contract remain authoritative.

## Visual acceptance

The parent reviewed actual simulator captures rather than accepting worker
reports as visual evidence. Six screens were accepted on iPhone 17 and iPad in
light and dark appearances (24 captures at `23c3500`). Six iPad landscape
captures passed at `9602bd5`. Initial accessibility captures exposed cramped
metadata and book actions; these were corrected and rechecked at `9602bd5`.
Four additional accessibility XXXL captures at `2aa0ecd` verify lower metadata,
photo actions, the book Pages action, and the native project editor.

The review also reduced oversized artwork and controls, moved Overview counts
below the collection, and corrected a fixture-image transport regression.
Screenshot tests assert that detail artwork has actually loaded.

Phone review copies:

- [Light appearance](https://clare.lakebed.app/?bulletin=fe59b0b4-cfdd-491c-a2bc-e70b9c5583d2)
- [Dark appearance](https://clare.lakebed.app/?bulletin=af14b024-c964-4d6c-8257-c21aa1dbee3e)

Full-resolution captures, logs, and the revision manifest are local at
`/tmp/og-redesign-evidence/`. Generated boards and fictional screenshot artwork
are not customer content.

## Functional and automated checks

- All 116 unit tests in 22 suites passed at `6f08b9e`, including photo preparation,
  multipart authentication replay, uncertain-write recovery, date-only handling,
  scoped pagination, stale-response protection, and artwork cache cancellation.
- The native Photos picker selected a seeded image, uploaded it, and displayed
  the appended page photo at `7f2ee80`. Picker cancellation is also covered.
- Stateful UI coverage exercises project edit/cancel/save/delete, book-to-page
  navigation and pagination, search/status/sort, craft switching, Overview
  Wishlist/Completed handoffs, and loading/empty/error states.
- Full repository gate passed at `ca949c9`: 116 unit tests and 25 UI test
  cases, with 8 explicit UI skips and no failures. Opt-in photo selection and
  live-backend writes passed separately; iPad layout was verified in the capture
  matrix. Skipped system accessibility automation is not a VoiceOver pass.
- Live backend UI create/edit/delete passed at `baa454c`, including persisted
  title/status edits and confirmed deletion.
- Unsigned Release simulator archive succeeded at `7f2ee80`. Inspection of its
  compiled asset catalog found no fixture artwork. This is not a signed device
  archive or App Store distribution validation.
- Seven independent source-review specialties ran. Findings were repaired and
  rechecked; the final cancellation follow-up was clear at `9602bd5`.

## Evidence boundaries

Deterministic screenshots run the production SwiftUI hierarchy and concrete
PocketBase client through Debug-only fictional responses. They demonstrate
layout and interaction behavior, not production authorization or deployment.

Write integration uses an isolated PocketBase 0.37.5 instance with schema and
hooks from backend revision `6aff8ce42e7360513131a10ceb1c9478afb828f8`.
The real roundtrip creates a project and progress-note image, creates a book,
appends two page photos separately, refetches both, and cleans up. This verifies
the pinned contract; it does not claim that revision is deployed to production.
No backend schema or backend contract changes are included.

Routine simulation uses iOS/iPadOS 26.5. The deployment target remains iOS 18;
an iOS 18 runtime is not installed, so runtime compatibility on that version has
not been demonstrated. A hands-on VoiceOver navigation/listening pass is still
required before release. Source accessibility review, accessibility-tree
inspection, and Dynamic Type captures do not substitute for that pass.

## Reproduction

Run `cd ios && xcodegen generate`, then `./ios/script/pre-pr.sh` from the repo
root. Set `DESTINATION` to the intended iOS 26 simulator when necessary.
Capture tests accept `TEST_RUNNER_SCREENSHOT_DIR`; the six-screen test also
accepts `TEST_RUNNER_SCREENSHOT_ORIENTATION=landscape`. Accessibility detail
capture is opt-in with `TEST_RUNNER_RUN_REFINEMENT_AX_CAPTURE=1` and requires
setting the simulator's text size first. Native photo selection is opt-in with
`TEST_RUNNER_RUN_PHOTO_PICKER_UPLOAD=1` after seeding synthetic media.

Seeded backend tests require an isolated instance and explicit test credentials
through the documented test environment variables. Never use customer accounts
or commit a local backend override or test credentials.
