# Local personal build

Source head: `d68ab372f1c5488fcf8f3713cffd20b9a238a3ed`.
Build ID: `og-d68ab372-debug-1`.
Upstream pin: `737f2e881483a4c7237b49d5696adff7d44cad1b`.

The existing development identity and Xcode-managed profile signed the native
Debug archive. Automatic signing used the existing team; provisioning updates
were not enabled. An initial manual-signing attempt failed because the profile
is Xcode managed and dependency resource targets cannot use an app profile.
The automatic-signing retry passed.

An offline helper called the adapted Squircle library's existing
`overlay::framework` and `overlay::inject` functions. The device framework built,
was injected between archive and export, and the app was re-signed. No service
was started. The helper and signing/export configuration are local preparation
files, not additional application sources or tracked credentials.

All build, assembly and export commands ran through process-gate with waiting
enabled. The personal export uses `method=debugging`, `destination=export` and
existing automatic signing. No upload, App Store or TestFlight action ran.

## Verified artifact

Local IPA: `/tmp/og-squircle-personal-export/OrganizedGlitter.ipa`.
SHA-256: `4967b7daf04397723891c0bb946648b8c06d25bacf7d1dcd5f0e7e4004569dd6`.

The exported arm64 app passes `codesign --verify --deep --strict`, contains and
links SquircleOverlay, and retains the original host entitlements exactly. No
shared Keychain group was added. No `client.json` or `client-t3.json` is bundled;
no enrollment credential file was generated for this build. The embedded
development profile lists three devices. This does not establish whether the
selected acceptance device is among them.

Receipts are local: `/tmp/og-squircle-archive-signing-evidence.json`,
`/tmp/og-squircle-injected-archive-evidence.json`,
`/tmp/og-squircle-personal-build-evidence.json`. Sanitized logs:
`/tmp/og-squircle-native-debug-archive-2.log`,
`/tmp/og-squircle-offline-injection.log`,
`/tmp/og-squircle-personal-export.log`.

## To try after connectivity is approved

1. Establish trusted HTTPS endpoints for the existing T3 managed endpoint and
   the adapted build service. Keep the Mac awake; preserve T3 authorization and
   existing coordinator settings. Do not expose either service or change network
   sharing without approval.
2. Privately provision the enrollment file described in README.md. Never put it
   in app resources, the repository, screenshots or chat.
3. Confirm that the device is covered by the signing profile and explicitly
   authorize installation. This IPA uses the normal application's bundle ID,
   `com.interactivebuffoonery.organizedglitter`; installing it targets the same
   app identity. Do not assume an existing installation may be replaced.
4. Use an expiring HTTPS manifest/IPA link, confirm installation, and manually
   open the app. Open Developer tools, import enrollment, and explicitly connect.
5. Verify the reported build ID is `og-d68ab372-debug-1`, then test a message,
   reviewed screenshot attachment, activity, a question, explicit approval and
   denial, cancellation, disconnected reconnect, and forget/re-enrollment.

No live RPC, launch acknowledgement, physical installation, cellular download,
iPhone/iPad UI interaction or finite-background behavior has been verified.
A successful export is not a usable-workflow claim.
