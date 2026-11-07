# Compiler verification

Upstream pin: `737f2e881483a4c7237b49d5696adff7d44cad1b`.
Prepared source: `/tmp/og-squircle-final-source`.
Fresh reproduction: `/tmp/og-squircle-compiler-repro-2`.

The SHA-256 of the sorted tracked-file digest manifest, excluding XcodeGen's
regenerated `project.pbxproj` and including the separately copied enrollment
source, is identical for both checkouts:
`7d8b4d64a73776955158c3f0e449d7246079b2f171266fcbbdb2fc40a2179f4e`.
Manifests: `/tmp/og-squircle-final-source-manifest.sha256` and
`/tmp/og-squircle-compiler-repro-2-manifest.sha256`.

## Errors and resolutions

- `AgentStep.SizeTable.file`: expose the immutable, Sendable cache URL outside
  the main actor; media cache bookkeeping stays on the main actor.
- `ClientModels`: make the two immutable agent-instance Strings nonisolated.
- Enrollment: replace the nonexistent SwiftUI live-region modifier with the
  repository's `AccessibilityNotification.Announcement` pattern on status change.
- Quick Look: isolate only the delegate conformance to the main actor, matching
  the controller and its view access. No preconcurrency escape is used.
- Screen recording: compute the non-Sendable pixel attributes per use, carry the
  display name as a Swift String between actors, and keep conversion on its
  caller's executor with `nonisolated(nonsending)`. Pixel buffers remain owned by
  the encoder while the GPU completion is awaited.
- Events: make weak-self member access explicit.
- Theme and view helpers: isolate feedback generators and UIKit factories to the
  main actor; preserve safe constants. Use an explicit addSubview closure.
- Transport: add checked Sendable conformance to immutable configuration and
  HTTP clients; the service client's mutable validation cache remains locked.
- Display links: use isolated destruction for actor-owned UIKit state and mark
  the display-link proxy as main actor. Attachment providers remain on that actor.
- GPU and simulator render bookkeeping: use synchronous NSLock critical sections
  for shared reference-bearing state. Unlike sending Mutex closures, these do
  not transfer aliased Metal/render objects out of their synchronization domain.
  No new unchecked Sendable conformance is added. GPU completion captures only
  identity and retrieves retained pass objects through the lock.
- H.264: use a per-frame result pointer with the C output callback. Both decoder
  flags remain disabled; the SDK's synchronous DecodeFrame contract bounds the
  pointer's lifetime. This removes concurrently captured mutable local variables.
- Rust SQL tests: explicitly type two empty result vectors; expect the existing
  V2 assistant message as well as the rival thread reply. The focused projection
  test now passes; no production SQL was changed by these compiler fixes.

## Commands and evidence

All compilation and Rust tests run through process-gate with waiting enabled.
The original queued Swift build exited 65. Retries 1 and 2 exposed further Swift
6 errors. Retry 3 passed; retry 4 caught an optional-self typo introduced while
fixing warnings. Retry 5 passed after its correction.

```sh
process-gate xcodebuild -project /tmp/og-squircle-final-source/app/Squircle/Squircle.xcodeproj -target SquircleOverlay -configuration Release -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

`/tmp/og-squircle-compiler-build-5.log`: **BUILD SUCCEEDED**, exit 0.
The framework is a Mach-O universal library containing arm64 and x86_64.
Swift remains version 6 with complete concurrency checking. This compiles the
standalone overlay using Release optimization; injection into the host remains
Debug-only. No production native target was changed.

Full compiler errors and warnings, grouped by build attempt:
`/tmp/og-squircle-compiler-diagnostics.json`. Original log:
`/tmp/og-squircle-queued-build.log`; retry logs:
`/tmp/og-squircle-compiler-build-{1,2,3,4,5}.log`.
Remaining upstream warnings include deprecated APIs, unused values, a switch
pattern's `where` scope, weak capture spelling and Motion's UIKit reduced-motion
read. They are not reported as runtime-verified behavior.

Rust initially failed to compile two ambiguous empty-vector assertions, then ran
92/93 passing library tests with the stale V2 reply expectation failing. After
the assertion correction, the focused test passed (exit 0):
`/tmp/og-squircle-compiler-rust-focused.log`.

```sh
process-gate cargo test --locked
process-gate cargo build --locked
```

Full suite: `/tmp/og-squircle-compiler-rust-full.log`, exit 0: **99 passed, 0
failed**, across library, binary and integration tests (93 + 1 + 1 + 2 + 2).
This includes the source/release guards and export-policy tests. Initial Rust
logs: `/tmp/og-squircle-compiler-rust-test{,-2,-3}.log`.
Service binary build: `/tmp/og-squircle-compiler-rust-build.log`, exit 0.
Final committed-source Swift recheck: `/tmp/og-squircle-compiler-head-build.log`.


Preparation, check-invariants.py, check-sql.py's in-memory fixture, all 19
read-only live-database EXPLAIN checks, and git diff --check passed against the
fresh reproduction. No user rows were read. XcodeGen's generated project and
build artifacts are excluded from the integration patch.

## Evidence limits

This is compiler and test evidence. Enrollment UI, H.264 playback, recording,
reconnection, live RPCs, signing, physical installation, HTTPS reachability and
normal host Release artifact exclusion still require their separate checks.
Fresh independent review belongs to the coordinator. No service was started,
no device acquired, no public update made, and no authority changed.
