# Social sign-in parity for iOS

Updated: 2026-09-27. Status: Google/Discord enabled in Debug and Release for prelaunch testing; Apple and public-launch checks pending.
Planning branch: `feat/social-sign-in`, created from `origin/main`.
Simulator evidence and remaining checks: [social-oauth-validation.md](social-oauth-validation.md).

## Goal and boundaries

Support email/password, Apple, Google, and Discord on iPhone and iPad. The same
provider identity must reach the same PocketBase user record on web and iOS.
Never merge accounts or attach identities based only on matching email.

- Keep PocketBase as the only backend and identity system.
- Keep `PocketBaseClient` concrete and use one session-publication path.
- Use Apple APIs before dependencies. Support iOS 18; use iOS/iPadOS 26 for
  routine simulator verification and physical devices for provider flows.
- Keep server records in memory. Do not introduce offline writes or record caches.
- Backend routes, hooks, migrations, and token storage belong in
  `Interactive-Buffoonery/organized-glitter`, targeting `dev`.
- Update `ios/BackendContract.json` only after verifying the referenced backend
  revision. Source compatibility and production deployment are separate checks.

## Architecture and deliberate choices

Apple uses the native Sign in with Apple sheet and a backend code-exchange route.
Google and Discord use PocketBase OAuth2 through `ASWebAuthenticationSession`,
with the existing backend callback delivering the code over realtime.

```text
Google / Discord
  iOS -> PocketBase auth methods -> subscribe to @oauth2
      -> system auth browser -> provider -> PocketBase OAuth redirect
      -> realtime callback -> PocketBase code exchange -> session publication

Apple
  iOS native sheet -> Apple authorization code + attempt nonce
      -> native Apple backend route -> Apple token endpoint
      -> validate claims -> resolve/create PocketBase identity + store grant
      -> PocketBase auth response -> session publication

All methods
  persist and accept session through the shared ordering rules
      -> publish the signed-in account in AppModel
```

Native Apple is a product choice that adds backend maintenance. If that choice
changes, first spike browser-based Apple with the existing web Services ID: it
may remove the custom route. Do not build both Apple implementations by default.

Use a small `ASWebAuthenticationSession` adapter with explicit dismissal and a
presentation anchor for the initiating scene. Do not maintain a second SwiftUI
web-auth wrapper or build a generic authentication framework.

## Evidence and assumptions

The review inspected native source, the backend auth hook and ADR-0007, Context7
documentation, and PocketBase 0.40.4 source. Production provider configuration,
Apple console settings, and device flows were not verified.

- PocketBase's Apple provider validates the configured client ID. A provider
  configured for the web Services ID is not interchangeable with native
  authorization for the bundle ID.
- PocketBase supports realtime OAuth and manual code exchange. The realtime
  connection must stay active while authorization completes.
- Standard OAuth account creation includes an internal record-create request,
  identity linking, and verification transitions. A direct record save is not
  automatically equivalent to the complete request path.
- Standard OAuth can mark matching or empty-email accounts verified. The backend
  ADR uses `verified` as permission to access the application, not proof of
  password knowledge or necessarily of a nonempty verified email.
- `recordAuthResponse` enforces the collection auth rule and participates in
  shared auth hooks, MFA, and login-alert behavior.
- The backend hook blocks unauthenticated attachment by matching email and
  requires single-use step-up proofs for provider linking/unlinking.
- ADR-0007's statement that Apple was disabled on 2026-09-20 is historical,
  not current production evidence.
- The original plan identifies PR #5, native password reset, as the owner of
  session-publication ordering. Recheck its status and implementation before
  coding. This planning branch is not yet stacked on that PR.
- Do not infer web/native Apple identity continuity solely from console setup.
  Verify the resulting PocketBase record is identical in both directions.

## Phase 0: resolve prerequisites and run narrow spikes

### Repository and deployment checks

1. Refresh native `main`, PR #5, and the backend `dev` state. Confirm the deployed
   PocketBase version and source revision separately from the source pin.
2. If PR #5 has landed, use the main branch containing it. Otherwise base native
   implementation on its current reviewed head and retain the stacking dependency.
3. Read current backend creation hooks, rules, schema, and deletion design.
   Record the exact JSVM creation path and validation/hooks it invokes before
   implementing native Apple. Do not assume `RecordUpsertForm` or `app.save`
   reproduces an internal record-create request.

### Provider configuration

1. Inspect Apple configuration before enabling or changing it. Use test accounts
   for setup; avoid admitting production Apple users before grant capture exists.
2. Enable Sign in with Apple for App ID
   `com.interactivebuffoonery.organizedglitter`; verify its association with the
   web Services ID and the correct primary App ID in the same developer team.
3. Register the domain/sender used for verification and reset mail with Apple's
   private email relay service, and test actual delivery.
4. Configure backend secrets using the deployment's secret mechanism:
   `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, and
   `APPLE_NATIVE_CLIENT_ID`. Use a Sign in with Apple key, not an App Store
   Connect API key. Never include values in this document, source, or logs.
5. Verify Google and Discord allow the exact environment-specific
   `https://<pocketbase-host>/api/oauth2-redirect` URI. No console change is
   expected if that callback is already registered.

### Device spikes and exit criteria

- Google/Discord: prove subscribe-before-present ordering, code delivery,
  explicit browser dismissal, user cancellation, app switching, connection
  loss, and a fresh retry. Include an iPad presentation anchor check.
- Apple: with disposable accounts, prove web-first and native-first sign-ins
  resolve to the same PocketBase record, including Hide My Email. Do not log
  identity values or tokens as evidence.
- If realtime cannot survive the supported device flow reliably, reconsider a
  direct callback and manual code-exchange design before implementing the full
  helper. Do not hide that failure behind an automatic reconnect system.

## Phase 1: backend Apple support and grant capture

### Availability and request contract

Add guest-only `POST /api/auth/apple/native` with a 4096-byte body limit and an
explicit, tested rate-limit rule covering this custom route.

Request: `{ code, nonce, name? }`. The nonce is the raw, per-attempt random value;
iOS sends its SHA-256 hex digest to Apple. Validate types and bounded lengths,
reject missing/empty code or nonce before contacting Apple, and treat the
optional name only as user-supplied profile data. Do not accept a client token,
email, user ID, or verification flag as identity authority.

Define one native-Apple availability condition: users OAuth is enabled, Apple
is configured/enabled, and native configuration is valid. Enforce it on every
authentication request. Expose only the readiness boolean through a small
documented public response so the UI can use the same decision; settle the
response location during implementation. Do not create a generic capabilities
framework. Disabling Apple must stop this route as well as the web path.

### Token exchange and trust boundary

1. Mint a short-lived client secret, targeting five minutes, using the supported
   `AppleClientSecretCreateForm` API; verify its exact JSVM usage in the pinned
   runtime.
2. POST to the fixed `https://appleid.apple.com/auth/token` endpoint with the
   native client ID, client secret, code, and authorization-code grant type.
   Do not include a web redirect URI for native authorization codes. Bound the
   request timeout and response size.
3. Validate the successful response and required ID-token claim types, issuer,
   native audience, future expiry, nonempty subject, and nonce digest match.
   Reject missing, empty, malformed, or mismatched claims.
4. OIDC permits TLS server validation instead of signature verification for an
   ID token received directly from the token endpoint. This exception requires
   normal certificate validation and a trusted fixed endpoint; it never applies
   to a token supplied by the client. Prevent redirects to an untrusted endpoint.
5. Any mock token endpoint belongs exclusively to the test harness. An ordinary
   production environment override must not be able to redirect this trust
   boundary to an arbitrary server.

### Identity and verification policy

Resolve identity inside one database transaction, scoped to the users collection:

1. An Apple external-auth relation for the validated subject selects its existing
   user. Never change ownership by email or by client request.
2. If there is no relation but the provider email matches an existing account,
   return 409 and direct the user to sign in and connect Apple from web Account
   settings. Use the same collision policy as the existing OAuth hook.
3. Otherwise create the user with a random password, hidden email, appropriate
   profile fields, and an Apple external-auth relation. Preserve required
   validation and creation hooks using the concrete path established in Phase 0.
4. Preserve the established backend OAuth verification policy deliberately.
   Do not replace it with `verified = email_verified` silently. Specify and test
   missing email, missing/false verification claims, matching email, and an
   existing unverified linked user. Any policy change must be backend-first,
   documented for both clients, and reviewed before this route ships.
5. Include the existing OAuth security transitions for unverified accounts where
   applicable, including password/link handling; do not blindly mark every
   existing account verified. Use the pinned OAuth source as the comparison.
6. Store the successful Apple grant securely as part of the accepted identity
   operation. Roll back user/link/grant writes together on database failure.

Keep a shared helper for the email-collision decision where useful, but do not
mistake that extraction for full OAuth parity. Do not copy the entire provider
framework into a custom route.

Return the standard `$apis.recordAuthResponse(e, record, "oauth2", { isNew })`
after the transaction, with the intended auth request context. Test auth-rule
rejection and ensure no partial or stale session is published by the client.

### Grant capture starts here, not at App Store submission

Capture Apple refresh tokens in both native and web flows before enabling
production Apple enrollment. Store them encrypted on the backend, associated
with the account, provider identity, and client ID. Define encryption-key
handling, access restrictions, and replacement behavior; never return stored
grants in normal auth responses or record APIs. Do not overwrite an existing
usable grant with an absent token.

Coordinate with the backend account-deletion work now: define revocation,
retryable failures, and the point at which grant material can be removed.
Retain enough protected state to retry revocation without restoring access to
a deleted account. Existing Apple users with no stored grant need an explicit
recovery path, such as fresh authorization; earlier discarded tokens cannot be
recovered merely by adding storage later. The deletion UI may land separately,
but the complete deletion flow remains a release gate.

### Failure and retry contract

| Failure | Trigger | Response and resulting state |
| --- | --- | --- |
| Invalid request | Missing/empty/malformed code, nonce, or claims | Reject; no identity writes or session |
| Apple unavailable | Provider disabled or native configuration invalid | Provider-unavailable response; no exchange/session |
| Authorization rejected | Expired/reused code, `invalid_grant`, claim mismatch | Generic authentication error; fresh authorization required |
| Upstream failure | Timeout, connection failure, Apple 5xx | Temporary service error; no automatic reuse of the code |
| Identity collision | Email belongs to an account without this Apple identity | 409; no attachment; web settings recovery |
| Database failure | User, external-auth, or grant write fails | Transaction rollback; begin a fresh authorization attempt |
| Unknown completion | Code consumed or account committed, but response lost | Stay signed out locally; fresh authorization resolves existing identity |
| Auth-rule rejection | Resolved record cannot authenticate | No session; explicit recovery appropriate to the policy |

Do not introduce a general idempotency service for single-use Apple codes. A
fresh attempt plus identity lookup handles committed-account recovery. Never
log credentials, codes, tokens, nonce, email, subject, private URLs, or user data.

### Backend validation and handoff

Extend the disposable PocketBase auth harness with a controlled mock exchange.
Cover new/existing identity, collisions, absent email/name, verification-policy
cases, malformed responses/claims, wrong issuer/audience/nonce, expired tokens,
replayed codes, disabled providers, guest-only access, rate limiting, transaction
rollback, concurrent first sign-ins, response loss, grant storage failures, and
unchanged web OAuth/linking behavior. Verify required create hooks actually run.

Update ADR-0007 and `docs/API_CONTRACT.md` with the route, readiness response,
verification policy, error mapping, grant storage, and deployment requirements.
Land backend changes first, deploy through the authorized release process, and
verify the deployed revision and live provider flows before native release.

## Phase 2: Google and Discord on iOS

This lane can proceed independently of the native Apple route after the device
spike and session-ordering dependency are resolved. It is not independently
ready for App Store release.

Add focused transport methods to `PocketBaseClient`:

- Decode configured OAuth providers from auth methods, including name, state,
  auth URL, and code verifier. Keep per-attempt values in memory only.
- Open `/api/realtime`, parse `PB_CONNECT`, and subscribe to `@oauth2` using its
  client ID. Confirm subscription success before presenting the browser.
- Build the authorization URL using URL components, the exact encoded backend
  redirect URI, and the realtime client ID as state; retain PKCE parameters.
- Exchange the accepted code with the same provider, verifier, and redirect URI.
  Send guest auth requests without an existing account's authorization header.

Use one bounded attempt with these transitions:

```text
idle -> connecting -> subscribed -> authorizing
  -> callback accepted -> exchanging -> persisting -> signed in
  -> user cancelled / provider denied / disconnected / timed out -> signed out
```

The browser callback may report user cancellation or presentation failure.
Receiving a valid realtime callback must mark it accepted before programmatic
browser dismissal, so expected dismissal cannot cancel the code exchange.
Only one terminal outcome may win. Explicit user cancellation/navigation away
must invalidate the attempt; ignore late callbacks and results after sign-out
or a newer attempt. All terminal paths close the stream and release the browser.

Handle provider error events, empty codes, wrong state, malformed SSE, EOF,
subscription failure, and a bounded overall timeout. After connection loss,
start a new attempt with new state; do not assume a missed callback is replayable.

Persist and publish through the same ordering mechanism used by password auth
and PR #5. Cover cancellation during exchange and Keychain failure, not only
cancellation while the browser is visible.

Show Google/Discord only when configured. Map conflict, cancellation, disabled
provider, offline, temporary failure, and verification recovery intentionally;
do not show password-specific error copy for provider failures.

Tests: auth-method decoding; URL/PKCE preservation; subscription ordering; SSE
parsing; error/timeout cleanup; cancellation/success races; stale results;
session persistence failure; and provider-button UI using stubbed responses.

## Phase 3: native Apple on iOS

After the backend contract is verified:

- Add the Sign in with Apple entitlement and verify signing configuration.
- Use `SignInWithAppleButton`, requesting full name and email. Generate a fresh
  nonce with `SecRandomCopyBytes`, fail if generation fails, and send its
  SHA-256 hex digest through the request using CryptoKit.
- Validate that `authorizationCode` exists and decodes as nonempty UTF-8. Send
  code, raw nonce, and optional name to the backend. Missing name is normal on
  subsequent authorizations and must not erase a stored profile name.
- Publish through the shared session path. Treat `ASAuthorizationError.canceled`
  as normal and invalidate stale attempts consistently with other providers.
- Place Apple first when native Apple is available. Do not infer its availability
  from Google/Discord. Define the UI behavior for readiness-fetch failure and
  mid-attempt provider disabling, while retaining email access.
- Pin the verified backend revision once as part of native integration, including
  the route and readiness-response contract.

Google/Discord are enabled in Release builds for owner prelaunch testing.
Complete native Apple sign-in support before the planned public App Store launch.
Confirm the current App Store login-service requirements at release review;
the release gate is an operational provider test, not merely a visible button.

## Phase 4: release verification

- Complete backend account deletion, grant revocation and retry behavior, and the
  native deletion UI required by `architecture.md`. Verify native and web grants
  and accounts created before token capture.
- On physical iPhone and iPad, test all four sign-in methods, web/native identity
  continuity in both directions, existing Discord-only accounts, email collision,
  Hide My Email delivery, repeat Apple authorization without name, cancellation,
  app switching, network loss, and retry after unknown completion.
- Verify VoiceOver, Dynamic Type, keyboard/focus behavior, iPad presentation, and
  availability guards for APIs newer than iOS 18.
- Verify current provider configuration and the actual deployed backend revision.
  Contract tests alone do not establish production readiness.

## Scope limits

Native provider linking/unlinking remains separate; link to web Account settings
with clear recovery instructions and never transfer a bearer token in that URL.
Launch-time Apple `getCredentialState` checks remain deferred; document this as
a lifecycle limitation rather than claiming immediate detection of revocation.
Do not add general repositories, persistent attempt storage, reconnect machinery,
or a second identity system for this work.

## Resume checklist

1. Confirm the working branch and repository state; read this plan and architecture.
2. Refresh PR #5 and the backend/deployment facts; choose the implementation base.
3. Settle verification cases, exact creation API, readiness response placement,
   and secure grant storage/deletion handoff before writing the Apple route.
4. Run the two device spikes and record their outcomes without private data.
5. Implement backend and native changes through separate reviewed PRs, preserving
   their dependency order. This planning commit does not authorize deployment.

## References used in the review

- [PocketBase authentication](https://pocketbase.io/docs/authentication/)
- [PocketBase custom routes](https://pocketbase.io/docs/js-routing/)
- [PocketBase 0.40.4 OAuth implementation](https://github.com/pocketbase/pocketbase/blob/v0.40.4/apis/record_auth_with_oauth2.go)
- [PocketBase 0.40.4 auth response](https://github.com/pocketbase/pocketbase/blob/v0.40.4/apis/record_helpers.go)
- [PocketBase 0.40.4 Apple provider](https://github.com/pocketbase/pocketbase/blob/v0.40.4/tools/auth/apple.go)
- [Apple web authentication session](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [Apple user cancellation](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsessionerror/canceledlogin)
- [Apple identifier grouping](https://developer.apple.com/help/account/capabilities/group-apps-for-sign-in-with-apple/)
- [OIDC ID-token validation, section 3.1.3.7](https://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation)

Consult current Apple token-revocation documentation during the deletion work;
the review did not successfully retrieve its full technical note. Revalidate
version-specific API details with Context7 and the pinned source when coding.
