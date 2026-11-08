# Automatic personal updates

Sarah authorized this workflow for feature threads launched by the
[in-app dispatcher](DISPATCHER.md) into their own T3-managed worktrees. The
dispatcher never implements or builds in its bound PR98 checkout. After
implementing a requested native-app change in the feature worktree, complete the required
checks and fresh review, then build and offer a personal update without asking
for another build request. Questions, research, failed checks, and changes that
do not affect the installed native app do not trigger a build. Batch one update
per completed request, rather than building after each edit.

This is a standing instruction to the Mac-side coding agent, not a file watcher
or a new scheduler. Squircle continues to own its build queue, archive, overlay
injection, signing, export, artifacts and installation links. The phone's direct
build-creation restriction stays in place.

## Before submitting

1. Read the checkout's AGENTS and applicable Serabi instructions. Keep the
   selected model and existing session approval settings. Honor ownership of
   other agents' files; commit only your own changes. Fetch and check existing
   work, the actual PR base and branch before starting feature work.
2. Finish required checks and review at the source revision being offered.
   Commit the requested change and verify the checkout is clean. Do not build
   someone else's in-progress edits. Coordinate with any other writer before
   submission; nobody may edit or switch this checkout during archive/export.
3. Generate the native Xcode project with `xcodegen generate --spec ios/project.yml`.
   Use the already approved local service, signing configuration, and HTTPS
   routes. Do not enable provisioning updates or read/print credential files.
   A new worktree needs its own ignored `ios/Config/Debug.local.xcconfig`.
   Populate only `DEVELOPMENT_TEAM` from the existing private export options'
   `teamID` field, without printing the plist or copying other private settings.
   Preserve an existing local config; if its team differs, report the mismatch
   instead of overwriting it or selecting another identity/profile.
4. Validate the prepared overlay with `check-invariants.py`, using the
   `overlay_project` parent recorded in the owned local `service-pid.json`.
   This checks the current patch and enrollment bytes as well as boundaries.
   If stale, refresh the owned prepared source using `prepare.py` and XcodeGen,
   then restart only the owned idle service with the new project. Follow the
   setup instructions in README; never silently use an old overlay or alter T3.

## Build and deliver

Run from the feature thread's own clean native checkout on the approved Mac,
never from the dispatcher/PR98 checkout. The private operator
helper already exists under `~/Library/Application Support/OrganizedGlitterDeveloper`.
Its export options and signing configuration remain local. Save the full
`git rev-parse HEAD` before submission.

```sh
DEV_BUILD_ROOT="$HOME/Library/Application Support/OrganizedGlitterDeveloper"
process-gate python3 "$DEV_BUILD_ROOT/build-personal.py"
```

Leave a busy job queued. Do not use `--no-wait`, bypass the gate or start another
build because admission is taking time. The helper holds the gate while Squircle
archives, injects and signs, exports, and waits for a terminal result. Preserve
the returned build UUID from this invocation; do not select the newest or last
successful build as a substitute. No thread notification is requested, avoiding
an automatic build-completion turn that could trigger another build.

If cancellation is requested, cancel only this UUID through Squircle and wait
for its terminal state while the helper still holds admission. Do not first
terminate the helper and leave its service-owned Xcode job running. Never cancel
another agent's jobs.

After success, confirm HEAD is unchanged and the checkout is still clean. If
either changed, do not offer this build as proof of the intended source. Run:

```sh
python3 developer/squircle/finish-update.py \
  --build-id RETURNED_BUILD_UUID \
  --head FULL_SOURCE_SHA \
  --origin EXISTING_APPROVED_HTTPS_ORIGIN \
  --receipt "$DEV_BUILD_ROOT/update-receipts/RETURNED_BUILD_UUID.json"
```

The finisher rejects failed, stale, dirty, wrong-project, Release, simulator,
overlay-disabled or provisioning-enabled jobs. It checks the embedded build ID,
strict exported signature, development entitlement, arm64 architecture, overlay
linkage, dedicated-thread marker and named enrollment resources. It creates a
one-hour link only after local artifact checks, refuses HTTP or cross-origin
delivery and redirects, and hashes downloaded IPA bytes against the signed
export. A failure produces no ready-to-install receipt or install URL on stdout.
Inspect diagnostics privately; do not return an older update instead.

Reply to Sarah with the verified private install-page URL, source SHA, build
UUID and expiry. State that installation and launch are pending. These links
carry expiring download tickets: share only in the private coding conversation,
never a PR, public documentation, source control, screenshot or third-party
artifact host. Receipt files are private and must stay outside the checkout.
Keep the Mac awake and Tailscale connected during building and downloading.

## User checkpoint and authority

Sarah opens the link in Safari, confirms installation and manually opens the
app. Enrollment normally survives an update; verify rather than assuming it.
Use the service's actual diagnostic launch event to acknowledge the exact build
UUID. Never fabricate a launch event. A downloaded IPA, valid signature, message
from the phone or successful old build does not prove the new build launched.

This workflow authorizes personal Debug archive/export and delivery only. It
does not grant merges, PR comments/review approvals, production deployment,
App Store/TestFlight publication, provider/model changes, broader approval
modes, global T3 changes, network changes, new signing arrangements or automated
physical installation. Ask only for a concrete decision that exceeds this
standing scope; ordinary personal rebuilds do not need repeat permission.

## Evidence

`test-finish-update.py` exercises stale/failed/dirty build rejection, wrong
recipes, signing intent, HTTPS origin restrictions, redirects and substituted
downloads without creating builds or sending launch events. Run through the
host's build/test gate. Test coverage and a successful existing-artifact check
do not prove the next requested change completed this automatic loop; that
requires the dedicated agent's next checked/reviewed build and manual launch.
