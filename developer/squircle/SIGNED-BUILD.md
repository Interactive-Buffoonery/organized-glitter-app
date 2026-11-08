# Personal build and connection evidence

Source head: `878ed6ca81318e2ae8fff4ecf6cf9503910aaace`.
Current build ID: `2b00b2d4-0bcb-47b7-950e-c28ecad14190`.
Upstream pin: `737f2e881483a4c7237b49d5696adff7d44cad1b`.
IPA SHA-256: `9d741a45eb16f71144a061f01bab23e4375cd38c43229af4d4d9824c70386125`.

## Managed personal build

The adapted Squircle service completed the native Debug archive, device overlay
build/injection, signing and `debugging` export. The Mac operator submitted and
waited for this job inside one process-gate admission. The gate remained held
through completion; no phone action or provider turn started the build.
The existing Xcode-managed development profile and identity signed the app;
provisioning updates were not enabled. An ignored local Debug xcconfig supplies
the existing team. Private export options use automatic signing and export only.

The exported arm64 app passes `codesign --verify --deep --strict`, contains and
links SquircleOverlay, and retains the original host entitlements exactly. No
shared Keychain group was added. No `client.json` or `client-t3.json` is bundled.
The profile lists three devices; the acceptance phone/iPad has not been matched
to that list. The embedded SquircleBuildID equals the service job UUID, enabling
real launch acknowledgement after enrollment. The first installed build connected
according to Sarah, but its client policy blocked launch receipts. This update
fixes that diagnostic-only path and routes to the dedicated developer thread.
Ten actual Swift policy cases passed, and fresh focused review approved both
changes with no findings. Launch acknowledgement for this update remains pending.

The earlier offline build `og-d68ab372-debug-1` established signing/injection,
but its custom non-UUID ID could not produce launch acknowledgement. Use the
managed build above for acceptance instead of that earlier IPA.

## Release exclusion

The normal signed Release device archive passes strict signature verification.
It contains no Squircle linkage, named overlay/enrollment resources, or scanned
overlay/enrollment/coordinator markers. Executable SHA-256:
`a23fccd8c45e843e1f05486b467946472cdd1e481e62dd8ce0d9e239f8e085f8`.
This archive used source head `d68ab372`. Later changes are confined to the
developer adapter and documentation; the native target and configuration are
unchanged. This is historical artifact evidence, not a new Release archive at
the current adapter head.
The earlier unsigned Release simulator artifact also passed exclusion inspection.
No App Store/TestFlight export, upload or release was performed.

## Approved local connectivity

The user approved reconnecting the existing tailnet, starting the local service,
and HTTPS routes 443 to loopback Squircle 8787 and 8443 to existing T3 3773.
Both HTTPS health checks passed certificate validation; Funnel is disabled.
No T3 global authorization/provider/model settings were changed.

A private-card one-time pairing token was exchanged for a separate
`orchestration:read orchestration:operate` session. Authenticated HTTPS shell
reads found both pinned projects and the existing coordinator. A protocol-2 WSS
subscription returned that coordinator's thread snapshot. These checks sent no
chat message or mutation command. The service reports T3 Connected. The dedicated thread also returned an HTTPS
shell entry and a matching protocol-2 WSS snapshot before this update was offered.

The installation page, manifest and IPA each returned HTTP 200 over HTTPS from
the Mac. The downloaded IPA SHA-256 matches the signed export. This proves the
Mac-side path, not cellular reachability or physical installation.

The service binary, pinned adapted source, private state, ignored signing
configuration, export options, and operator helper are prepared locally. The
operator must run the helper from the intended native checkout under
`process-gate python3 /absolute/private/path/build-personal.py`. It submits one
Debug job and keeps admission until a terminal result. Use a fresh request ID
for a new build. Do not run ungated builds on a gated host.

## Manual checkpoint

1. Confirm the selected device is covered by the profile and explicitly choose
   whether to replace the current Organized Glitter installation. The developer
   IPA uses the normal bundle ID `com.interactivebuffoonery.organizedglitter`.
2. With Tailscale connected, open the expiring install page in Safari, confirm
   installation, and manually launch the app. Do not treat a download as install
   or launch proof.
3. Transfer the private enrollment file directly to the phone (for example,
   AirDrop from the Mac and Save to Files). Never send it through chat, add it to
   resources, or expose it through the installation links. Open Developer tools,
   import that file, and explicitly connect. Forget removes the app-private
   Keychain enrollment; revoke the paired session separately on the Mac.
4. Verify the service observes the exact build UUID above. Then test a message,
   reviewed screenshot attachment, activity, question, explicit approval and
   denial, cancellation, dropped-connection reconnect, and forget/re-enrollment.

Sarah reported installing and connecting the previous build. This new update
still needs manual installation and exact-build launch acknowledgement. Cellular
download, iPhone/iPad interaction details, mutation-command behavior, reconnect
and finite-background behavior have not been independently verified.
Session expiry still requires renewed explicit enrollment; credentials are not
baked into this IPA.

Local receipts: `/tmp/og-squircle-dedicated-build-evidence.json`,
`/tmp/og-squircle-signed-release-exclusion.json`,
`/tmp/og-squircle-dedicated-live-readiness.json`,
`/tmp/og-squircle-dedicated-delivery-evidence.json`.
