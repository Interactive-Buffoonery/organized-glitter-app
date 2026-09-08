# Account entry validation

Date: 2026-09-07. Branch: `chore/native-ui-cleanup` in
`Interactive-Buffoonery/organized-glitter-app`.

## Design references

Adopted against `Interactive-Buffoonery/organized-glitter` branch
`design/ios-mockup-studio`, revision
`0135e6d3caa73ea01224bda27c8e0abbb954fd19` (verified 2026-09-07 via
`git fetch` / `git rev-parse origin/design/ios-mockup-studio`):

- `docs/design-previews/ios-mockup/README.md`
- `docs/design-previews/ios-mockup/client/phone.tsx` and `client/welcome.ts`
- `docs/design-previews/ios-mockup/COPY.md` and `STYLE.md`
- Studio QA captures saved under
  [screenshots/account-entry/references/](screenshots/account-entry/references/)

ADR 0001 remains authoritative for native palettes and backgrounds. The studio
diagonal splash gradient and simulated OAuth success paths are not product
contracts.

Backend auth ADR
[`organized-glitter` ADR 0007](https://github.com/Interactive-Buffoonery/organized-glitter/blob/dev/docs/adr/0007-auth-providers-and-token-model.md)
records Discord OAuth as live on the PWA, with Google and Apple planned. The
iOS app still has no native OAuth client path, so method selection offers only
Continue with email. Provider buttons are intentionally omitted rather than
shown as inert or “Soon.”

Supplied design images in the mockup studio `references/` folder are Wishlist
and Notes inspiration, not splash/welcome. Account-entry visual decisions use
the studio QA HTML mockups plus native simulator captures.

The App Store / home-screen icon was regenerated from
`Interactive-Buffoonery/organized-glitter` `dev` at
`b3b422a68f28d74388b487bc5134f75a01d61787` using `docs/icons/app-icon.html`
(square 1024 export). See
[references/app-icon-1024.png](screenshots/account-entry/references/app-icon-1024.png).

## Entry flow map

| Screen | Native destination | Backend contract |
| --- | --- | --- |
| System launch | `UILaunchScreen` + `LaunchBackground` + `LaunchWordmark` | None |
| In-app restore | `LaunchView` while `phase == .restoring` | Keychain + `authRefresh` |
| Welcome | `WelcomeView` | Navigation only |
| Method choice | `AccountMethodView` | Email only today |
| Email sign-in | `SignInView` | `authWithPassword` |
| Registration | `RegistrationView` | `register` + optional `requestVerification` |
| Password reset request | `PasswordResetView` | `requestPasswordReset` |
| Password reset confirmation | Same view, request-complete state | No token confirm |
| Verification request | `VerificationRequestView` | `requestVerification` |
| Offline / restore failure / config | `RootView` states | Session preserved on offline/failure |

## Implemented behavior

| Surface | Behavior |
| --- | --- |
| System launch screen | Solid `LaunchBackground` (`#F8E9F6` light / `#05051A` dark) with centered Caveat `LaunchWordmark` asset. |
| In-app restoration | Caveat wordmark plus unlabeled progress (VoiceOver: “Opening your library”) only while restoring. No artificial delay. |
| Welcome | Stacked Caveat wordmark, Create account, Sign in. Owns `NavigationStack` path. No authenticated tabs. |
| Method selection | Wordmark, Welcome back / Create account, Continue with email, switch link. Mode switches in place without stacking duplicate method screens. |
| Email sign-in | Email, password, Sign in, Forgot password?, Privacy, Terms, Resend verification. Password reset and verification use the shared path, not nested `NavigationLink` destinations. |
| Registration | Username, email, password, confirmation; success guidance after create. Sign in pops back to method choice in sign-in mode. |
| Password reset | Request form distinct from “Check your inbox” confirmation. |
| Verification request | Request form and confirmation guidance. |
| Offline / restoration failure / configuration error | Wordmark plus retry or configuration copy. |

Preserved: Keychain session storage, account identity, restoration, validation,
PocketBase register / request-verification / request-password-reset contracts,
and authentication unit tests.

## Selected screenshots

Native simulator captures (fictional signed-out fixtures):

- [iPhone Welcome, light](screenshots/account-entry/iphone-welcome-light.png)
- [iPhone Welcome, dark](screenshots/account-entry/iphone-welcome-dark.png)
- [iPhone method choice, light](screenshots/account-entry/iphone-signin-methods-light.png)
- [iPhone method choice, dark](screenshots/account-entry/iphone-signin-methods-dark.png)
- [iPhone email sign-in, light](screenshots/account-entry/iphone-signin-light.png)
- [iPhone email sign-in, dark](screenshots/account-entry/iphone-signin-dark.png)
- [iPhone register methods, light](screenshots/account-entry/iphone-register-methods-light.png)
- [iPhone register methods, dark](screenshots/account-entry/iphone-register-methods-dark.png)
- [iPhone registration, light](screenshots/account-entry/iphone-register-light.png)
- [iPhone registration, dark](screenshots/account-entry/iphone-register-dark.png)
- [iPhone password reset, light](screenshots/account-entry/iphone-password-reset-light.png)
- [iPhone password reset, dark](screenshots/account-entry/iphone-password-reset-dark.png)
- [iPad Welcome, light](screenshots/account-entry/ipad-welcome-light.png)
- [iPad Welcome, dark](screenshots/account-entry/ipad-welcome-dark.png)
- [iPad method choice, light](screenshots/account-entry/ipad-signin-methods-light.png)
- [iPad method choice, dark](screenshots/account-entry/ipad-signin-methods-dark.png)
- [iPad email sign-in, light](screenshots/account-entry/ipad-signin-light.png)
- [iPad email sign-in, dark](screenshots/account-entry/ipad-signin-dark.png)
- [iPhone Welcome, accessibility XXXL](screenshots/account-entry/iphone-welcome-axxl.png)
- [iPhone method choice, accessibility XXXL](screenshots/account-entry/iphone-signin-methods-axxl.png)

Studio QA and launch references:

- [Studio splash, light](screenshots/account-entry/references/studio-splash-light.png)
- [Studio splash, dark](screenshots/account-entry/references/studio-splash-dark.png)
- [Studio welcome, light](screenshots/account-entry/references/studio-welcome-light.png)
- [Studio welcome, dark](screenshots/account-entry/references/studio-welcome-dark.png)
- [Studio method choice, light](screenshots/account-entry/references/studio-signin-methods-light.png)
- [Studio email sign-in, light](screenshots/account-entry/references/studio-signin-email-light.png)
- [Studio email sign-in, dark](screenshots/account-entry/references/studio-signin-email-dark.png)
- [Studio register email, light](screenshots/account-entry/references/studio-register-email-light.png)
- [Studio recovery, light](screenshots/account-entry/references/studio-recovery-light.png)
- [Studio recovery confirmation, light](screenshots/account-entry/references/studio-recovery-confirmation-light.png)
- [Launch wordmark asset, light](screenshots/account-entry/references/launch-wordmark-light.png)
- [Launch wordmark asset, dark](screenshots/account-entry/references/launch-wordmark-dark.png)

Root `screenshots/light-signin.png` and `screenshots/dark-signin.png` match the
current email sign-in presentation.

## Verification

- Debug build for iPhone 17 succeeded.
- `OrganizedGlitterTests` passed (71 tests), including empty sign-in rejection.
- UI tests `testSignedOutAccountEntryPointsAreNative` and
  `testAuthenticatedShellShowsFiveDestinations` passed. The signed-out test
  walks Welcome → method choice → email form, asserts Apple/Google/Discord
  buttons are absent, checks empty-submit validation, method-mode switching,
  and registration → Sign in returning to Welcome back.
- Light/dark iPhone, light iPad, and accessibility XXXL account-entry
  screenshots were recaptured with fictional fixtures and compared to studio QA
  references.

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
  -only-testing:OrganizedGlitterUITests/ScreenshotCaptureTests/testCaptureAccountEntry
```

Manual review: launch Debug with `-ui-testing-signed-out`.

## Not tested in this batch

- Live email sign-in, registration, verification request, or password-reset
  against a real PocketBase instance
- Live Discord, Google, or Apple authentication (not implemented on iOS)
- Universal-link token confirmation for reset or verification
- System launch screen pixel comparison on device cold start
- iPad dark-mode and iPad accessibility XXXL account-entry matrices

## Remaining visual gaps

- Studio method choice shows Apple/Google/Discord; native shows email only by
  contract
- System launch cannot use a live Dynamic Type Caveat font; it uses the
  `LaunchWordmark` image asset on `LaunchBackground`
- Studio dark email CTAs use a light lavender fill; native quiet buttons use
  elevated card fill over the ADR navy glow
- Native method choice uses one capsule email row instead of four provider rows
- In-app restore splash was not captured as a still (restore exits immediately
  with signed-out fixtures)
- Accessibility XXXL captures may reflect host simulator text size; confirm on
  device if shipping release notes need exact AX sizing

## Backend / auth follow-ups

1. Add native Discord OAuth (ASWebAuthenticationSession or equivalent) after
   verifying production PocketBase provider config and existing Discord-only
   account continuity. Do not merge accounts by email.
2. Add Google and Apple only after provider setup and continuity checks; Apple
   becomes mandatory if Google or Discord ship in the App Store build
   (ADR 0007).
3. Ship Associated Domains, stable HTTPS universal-link routes, token format,
   and fallback behavior for password-reset and email-verification confirmation;
   then add native confirmation screens.
4. Keep password-reset request distinct from token confirmation.
5. Account deletion remains a separate backend-first App Store blocker per
   `architecture.md`.
