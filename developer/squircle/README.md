# Personal in-app development (runtime verification pending)

This integration reuses Squircle's MIT overlay and Rust build service at
`737f2e881483a4c7237b49d5696adff7d44cad1b`. It is not linked into the native
application target. `prepare.py` creates a new checkout and applies the tracked
patch; it refuses to overwrite any existing checkout. The upstream license is
included here. No upstream or T3 checkout is modified.

```sh
python3 developer/squircle/prepare.py /absolute/new/checkout
python3 developer/squircle/check-invariants.py /absolute/new/checkout
```

Generate that checkout's `app/Squircle` project with XcodeGen. Build its
`SquircleOverlay` target and Rust service through process-gate on Midnight Pro.
Do not use the unpatched stock service with this client. Set
`SQUIRCLE_OVERLAY_PROJECT` in the private service launch environment to the
prepared `app/Squircle/Squircle.xcodeproj`. Do not start or expose a service,
change signing, or configure a network endpoint as part of preparation.

The service injects only for configuration exactly `Debug`, only for upstream's
allowlisted personal distribution methods, and never for App Store exports.
It retains the host's existing signing entitlements without adding a shared
Keychain group. Normal Organized Glitter Release targets contain none of these
sources or resources. Artifact inspection remains required before distribution.

On launch the injected overlay asks to import a private JSON enrollment file.
The format uses upstream's `t3_url`, `t3_token`, `squircle_url`,
`squircle_token`, and `diagnostic_token` fields. Both origins must use HTTPS.
Supply the file privately, never in this repository, app resources, build
settings, logs or screenshots. Import stores it in the host application's
private Keychain with device-only, when-unlocked protection. Connect is an
explicit action; Forget removes the enrollment. Use Developer connection in the conversation menu to replace expired or
revoked enrollment; this closes the old connection before import. Continuing
without tools leaves a Developer tools button to reopen enrollment. Revoke leaked credentials on the Mac separately.

The project list is restricted to the existing web and native projects. Their
agent entry points resolve to the existing pinned coordinator. Sends require
that thread. The RPC boundary allows only message dispatch, run cancellation,
and explicit runtime-request responses for that coordinator. It removes mode
and model selection fields before dispatch. Project/thread creation, permission
mode changes and provider switches cannot pass this boundary. The service HTTP
boundary permits reads and explicit install-link creation only; build creation,
agent restart, and service-mediated approvals are disabled. Start builds on the
Mac after reviewing the requested change. Existing coordinator authority is
preserved; messages do not authorize merges, releases, comments or deployment.

Upstream supplies screenshot composition, attachment upload, conversation
activity, questions, approvals, cancellation, and cursor reconnection. These
paths are retained, but have not yet been exercised with this adaptation.
Screenshots are explicit message attachments: review them before sending.

For a signed update, the authorized operator builds the native Debug archive
with the adapted service and existing private export configuration. Select that
specific build's Install action, confirm installation manually, then manually
open the app. Verify the new build ID separately from download or install-link
success. Never replace a physical-device app without explicit authorization.

## Evidence and remaining work

Reproducible local preparation passed from the pinned clone into
`/tmp/og-squircle-repro`. Source boundary checks passed. See
[COMPATIBILITY.md](COMPATIBILITY.md) for installed protocol fields and limitations.
Both project cards use the existing T3 shell and require no catalog metadata.

All 19 SQL constants prepared against `statev2.sqlite` using read-only EXPLAIN,
without reading user rows. The executable in-memory V2 fixture passed message,
image, thread/project isolation and literal-search checks after dropping legacy
tables. Run:

```sh
python3 developer/squircle/check-sql.py /absolute/prepared/checkout
python3 developer/squircle/check-sql.py /absolute/prepared/checkout /private/path/statev2.sqlite
```

The original queued overlay build completed with exit **65** and exposed Swift 6
compiler errors (`/tmp/og-squircle-queued-build.log`). The compiler fixes and
subsequent verification are recorded in [COMPILER-FIXES.md](COMPILER-FIXES.md).
All retries used process-gate with waiting enabled; no failed build was rerouted.
No device was acquired or installed. Local signing, managed personal export,
approved service setup, and read-only live RPC subsequently passed; see
[SIGNED-BUILD.md](SIGNED-BUILD.md).
This remains a draft pending runtime and delivery checks.

At source head `6655d816aaf1b1150b97fcbfd088ae374ebee953`, the gated
Swift 6 overlay build passed for arm64 and x86_64. The Rust service built and all
99 tests passed. A fresh focused independent source review approved the compiler
fixes with no findings. These results do not establish runtime behavior.

The normal native Release simulator build also passed. Inspection found no
Squircle linkage, named overlay resources, or enrollment/coordinator markers.
The executable SHA-256 was
`57f7aa2000f8557b5489a26be41008f6511d84ac8d073436915235b7d054fe9e`.
Local receipts: `/tmp/og-native-release-exclusion.log` and
`/tmp/og-native-release-exclusion-evidence.json`. This is an unsigned simulator
artifact, not an archive/export or physical-distribution proof.

Before calling this usable: exercise enrollment/forget/re-enrollment and
reconnect under dropped connections; verify questions, approval denial/acceptance,
cancellation and screenshots against the pinned coordinator; then separately
establish authorized HTTPS reachability, confirm the selected device is covered
by the profile, and obtain manual device update proof. Personal Debug export
composition and signatures, signed Release archive exclusion, live read-only
protocol-2 RPC, and Mac-side HTTPS delivery passed. Mutation behavior and physical
installation remain unverified. T3's remote device listing
failed twice with “Could not reach the Simlock gateway”; no device was acquired
or driven through an alternate path.

## Focused review

The first fresh review found a non-Sendable static Info.plist dictionary under
Swift 6. The follow-up approved its replacement with stored String values.
Compilation then exposed further errors; see [COMPILER-FIXES.md](COMPILER-FIXES.md).
A fresh focused review of `5996111..6655d81` approved those compiler fixes with no
findings, including GPU locking, synchronous VideoToolbox callback lifetime and
actor isolation. This was source and SDK-header review, not runtime testing.

Local signing inspection found an available private-key identity with a matching,
unexpired development profile. The resulting signed Debug archive and personal
IPA passed verification. The profile lists three devices; the phone or iPad used
for acceptance has not been matched to that list. The user subsequently approved reconnecting the existing tailnet and two HTTPS
routes. Certificate-validated Mac-side health/download and read-only protocol-2
checks passed; cellular reachability and device behavior remain unverified.
