# Google and Discord OAuth validation

Updated: 2026-09-27. Branch: `feat/social-oauth`, rebased onto `main` after PR #5 merged.
This is a Debug-only integration layer. `AccountMethodView` hides provider controls
from Release builds until native Apple and the release gates in
`social-sign-in-plan.md` are complete.

## Rebase and cancellation review

Rebased onto `main` at `35a76ca`. Regenerated the Xcode project to resolve the
project-file conflict. Review fixes are in `95b23fb`:

- Session transitions cancel the task and invalidate its specific client attempt
  ID. Cleanup from an older attempt cannot invalidate a newer attempt.
- Tests cover model cancellation while waiting for a callback and during exchange,
  timeout, rejection of a late response without task cancellation, and delayed
  cleanup after a retry starts.
- Removed unused provider `state` decoding and the unused `OAuthError.timedOut`
  case. Callback state validation remains in place. Provider names and symbols
  now come from one `SocialProvider` mapping.
- `DESTINATION='platform=iOS Simulator,id=C3F25292-F37D-4B34-BBA7-7955D3883C06' ./ios/script/pre-pr.sh` passed on a dedicated iOS 26.5 simulator: 173 unit tests in 27 suites and the full UI suite, including provider buttons. Device-specific and opt-in checks were skipped where their prerequisites were absent.
- The Release simulator build passed with signing disabled.

The first full preflight on the shared iPhone simulator ended with two runner
exits in Overview UI tests and subsequently reported another worktree's test
paths. A dedicated simulator was created for the final preflight to avoid shared
app installations. Both affected Overview tests passed in that isolated run.

## Earlier simulator evidence

Device: iPhone 17, iOS 26.5 simulator. Derived data:
`/tmp/og-social-oauth-dd`.

- `xcodebuild -project OrganizedGlitter.xcodeproj -scheme OrganizedGlitter -destination 'platform=iOS Simulator,id=BD25AF72-E96B-47EB-81CA-4D62004D72A0' -derivedDataPath /tmp/og-social-oauth-dd -only-testing:OrganizedGlitterTests test` passed 152 tests in 26 suites. Log: `/tmp/og-social-oauth-alltests.log`.
- The same command with `-only-testing:OrganizedGlitterUITests/OrganizedGlitterUITests/testConfiguredSocialProvidersAppearInDebugAccountMethods` passed. The UI fixture showed both configured provider buttons. Log: `/tmp/og-social-oauth-uitest.log`.
- `xcodebuild -project OrganizedGlitter.xcodeproj -scheme OrganizedGlitter -configuration Release -destination 'platform=iOS Simulator,id=BD25AF72-E96B-47EB-81CA-4D62004D72A0' -derivedDataPath /tmp/og-social-oauth-dd CODE_SIGNING_ALLOWED=NO build` passed. Log: `/tmp/og-social-oauth-release.log`.
- A direct `URLSession.bytes(for:)` test with an SSE fixture delivered `PB_CONNECT` and `@oauth2` through the production byte parser. This caught that `AsyncBytes.lines` dropped blank event delimiters on this simulator; byte-level newline parsing now preserves them.
- The OAuth transport fixture proved subscription POST completes before browser presentation, the exchange request omits an existing bearer token, the backend redirect and PKCE verifier are preserved, and wrong-state, provider-denied, and sign-out-during-exchange paths do not save a session.

Using the assigned `agent-device` session, the installed Debug app showed Google and
Discord from configured auth methods. Discord presented the system sign-in
consent, then opened the Discord page in SafariViewService. Cancelling returned
to the signed-out method screen; a fresh attempt presented consent again.
Google presented its system sign-in consent and cancelled back to the same
screen. No credentials or identity were entered.

## Remaining release checks

This evidence does not establish successful live provider code exchange, web/iOS
record continuity, Keychain write failure recovery, iPad presentation behavior,
or physical-device app switching and network-loss behavior. Those checks remain
open, along with native Apple support, backend grant/deletion work, deployed
revision verification, and the wider release gates in the plan. The simulator
provider exercise covered presentation, cancellation, and retry only.
