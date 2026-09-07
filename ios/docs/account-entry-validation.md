# Account entry validation

Date: 2026-09-07. Branch: `chore/native-ui-cleanup` in
`Interactive-Buffoonery/organized-glitter-app`.

## Design references

Adopted against `Interactive-Buffoonery/organized-glitter` branch
`design/ios-mockup-studio`, revision
`0135e6d3caa73ea01224bda27c8e0abbb954fd19`:

- `docs/design-previews/ios-mockup/README.md`
- `docs/design-previews/ios-mockup/client/phone.tsx` and `client/welcome.ts`
- `docs/design-previews/ios-mockup/COPY.md` and `STYLE.md`
- Studio QA captures under `docs/design-previews/ios-mockup/qa/` for splash,
  welcome, sign-in method choice, and email sign-in

ADR 0001 remains authoritative for native palettes and backgrounds. The studio
diagonal splash gradient and simulated OAuth success paths are not product
contracts.

Conversation assets present in the Cursor project at implementation time were
unrelated Bugbot and review screenshots, not splash/welcome references. Visual
decisions used the mockup studio revision above plus ADR 0001.

## Implemented behavior

| Surface | Behavior |
| --- | --- |
| System launch screen | Solid `LaunchBackground` (`#F8E9F6` light / `#05051A` dark). No logo tile. Coherent with in-app splash without using Caveat on the system surface. |
| In-app restoration (`LaunchView`) | Caveat wordmark plus progress while `phase == .restoring`. Leaves as soon as restoration finishes. No artificial delay. |
| Welcome | Signed-out root. Stacked Caveat wordmark, Create account, Sign in. No authenticated tabs. |
| Email sign-in | Separate form: email, password, Sign in, Forgot password?, Resend verification, Privacy, Terms, Create account. |
| Registration | Separate email form with username, email, password, confirmation; success guidance after create/verification request. |
| Password reset | Request form distinct from confirmation ("Check your inbox"). No token confirmation or universal links. |
| Verification request | Request form and confirmation guidance. Native token confirmation remains blocked. |
| Offline / restoration failure / configuration error | Wordmark plus retry or configuration copy on the themed background. |

Preserved: Keychain session storage, account identity, restoration, validation,
PocketBase register / request-verification / request-password-reset contracts,
and existing authentication unit tests.

## Provider gap

Apple, Google, and Discord method buttons from the studio are not shipped.
There is no native OAuth client path, and production continuity for existing
provider accounts is not verified. Showing those buttons would be inert or
simulated success, both disallowed. Follow-up work belongs in the backend and
a later iOS change once providers and continuity are confirmed.

## Selected screenshots

Native simulator captures (fictional signed-out fixtures):

- [iPhone Welcome, light](screenshots/account-entry/iphone-welcome-light.png)
- [iPhone Welcome, dark](screenshots/account-entry/iphone-welcome-dark.png)
- [iPhone email sign-in, light](screenshots/account-entry/iphone-signin-light.png)
- [iPhone email sign-in, dark](screenshots/account-entry/iphone-signin-dark.png)
- [iPhone registration, light](screenshots/account-entry/iphone-register-light.png)
- [iPhone registration, dark](screenshots/account-entry/iphone-register-dark.png)
- [iPhone password reset, light](screenshots/account-entry/iphone-password-reset-light.png)
- [iPhone password reset, dark](screenshots/account-entry/iphone-password-reset-dark.png)

Adopted studio QA references from revision
`0135e6d3caa73ea01224bda27c8e0abbb954fd19` (kept for comparison; method-choice
screens include providers that are not shipped natively):

- [Studio splash, light](screenshots/account-entry/references/studio-splash-light.png)
- [Studio splash, dark](screenshots/account-entry/references/studio-splash-dark.png)
- [Studio welcome, light](screenshots/account-entry/references/studio-welcome-light.png)
- [Studio welcome, dark](screenshots/account-entry/references/studio-welcome-dark.png)
- [Studio email sign-in, light](screenshots/account-entry/references/studio-signin-email-light.png)
- [Studio email sign-in, dark](screenshots/account-entry/references/studio-signin-email-dark.png)
- [Studio method choice, light](screenshots/account-entry/references/studio-signin-methods-light.png)
- [Studio register email, light](screenshots/account-entry/references/studio-register-email-light.png)
- [Studio recovery, light](screenshots/account-entry/references/studio-recovery-light.png)
- [Studio recovery confirmation, light](screenshots/account-entry/references/studio-recovery-confirmation-light.png)

Root `screenshots/light-signin.png` and `screenshots/dark-signin.png` were
refreshed to the current email sign-in presentation.

## Verification

- Debug build for iPhone 17 succeeded.
- `OrganizedGlitterTests` passed (70 tests).
- UI tests `testSignedOutAccountEntryPointsAreNative` and
  `testAuthenticatedShellShowsFiveDestinations` passed.
- Native welcome, email sign-in, registration, and password-reset screenshots
  were captured in light and dark with fictional signed-out fixtures.
- Studio QA reference images from revision
  `0135e6d3caa73ea01224bda27c8e0abbb954fd19` are saved under
  `screenshots/account-entry/references/`.

### Reproduce

```sh
xcrun simctl ui <udid> appearance light
TEST_RUNNER_SCREENSHOT_DIR=/tmp/og-auth-shots/light \
xcodebuild test \
  -project ios/OrganizedGlitter.xcodeproj \
  -scheme OrganizedGlitter \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OrganizedGlitterTests \
  -only-testing:OrganizedGlitterUITests/OrganizedGlitterUITests/testSignedOutAccountEntryPointsAreNative \
  -only-testing:OrganizedGlitterUITests/ScreenshotCaptureTests
```

Manual review: launch Debug with `-ui-testing-signed-out`.

## Not tested in this batch

- Live email sign-in, registration, verification request, or password-reset
  against a real PocketBase instance
- Live Apple, Google, or Discord authentication (not implemented)
- Universal-link token confirmation for reset or verification
- iPad account-entry screenshot set and largest Dynamic Type screenshot matrix
- Keyboard-overlap regression on every form beyond interactive scroll dismissal
- System launch screen pixel comparison on device cold start

## Remaining visual gaps

- Studio method-selection screen with provider marks is absent by contract
- System launch cannot render Caveat; it uses the solid brand background only
- Welcome wordmark sits slightly higher than some studio frames; actions remain
  thumb-reachable above the home indicator
- Screenshot capture dismisses the keyboard before saving form screens; live
  autofocus still opens it during normal use

## Backend / auth follow-ups

1. Verify production PocketBase OAuth provider configuration and existing-account
   continuity for Apple, Google, and Discord, then implement native Sign in with
   Apple / ASWebAuthenticationSession flows without merging accounts by email.
2. Ship Associated Domains, stable HTTPS universal-link routes, token format,
   and fallback behavior for password-reset and email-verification confirmation;
   then add native confirmation screens.
3. Keep password-reset request distinct from token confirmation.
4. Account deletion remains a separate backend-first App Store blocker per
   `architecture.md`.
