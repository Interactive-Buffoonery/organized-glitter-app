# Native architecture

## Boundaries

- `OrganizedGlitter/App` owns configuration, session state, and root navigation.
- `OrganizedGlitter/Networking` owns concrete PocketBase requests.
- Feature folders own their views and feature-local state.
- `OrganizedGlitter/Design` owns semantic native styling. Tokens, hex values,
  and rules are documented in `docs/design.md`.
- `BackendContract.json` pins the backend source contract used for integration
  validation.

The application does not own backend schema or server behavior. Those remain in
`Interactive-Buffoonery/organized-glitter`.

## Data policy

- PocketBase is the only identity system and backend.
- Credentials are stored in Keychain.
- Records remain in memory for the process lifetime.
- Writes require connectivity.
- The app does not queue writes or claim realtime synchronization.
- Concurrent edits use PocketBase last-write-wins behavior.
- A write with unknown completion must be refreshed before retry.
- Library search, status filters, sorting, and pagination execute on PocketBase.
- File images are displayed via direct file URLs
  (`/api/files/{collection}/{recordID}/{filename}?thumb=WxH`) while file fields
  remain unprotected. The backend `docs/FILE_ACCESS_CONTRACT.md` (status:
  blocked by privacy audit, 2026-07-27) treats the unprotected state as a
  native public-release blocker requiring migration to protected fields plus
  short-lived file tokens. All file URL construction goes through
  `PocketBaseClient.fileURL` so the token flow lands in one place when that
  migration ships.

## Dependency policy

Use SwiftUI, Observation, URLSession, AuthenticationServices, Keychain
Services, PhotosPicker, OSLog, XCTest, and Swift Testing before adding a
dependency. Add a dependency only for a demonstrated platform gap.

## Release gates

The source contract workflow proves compatibility with a pinned backend commit
and local PocketBase version. It does not prove which revision is deployed to
production.

Before App Store submission, the release owner must separately verify:

- Deployed backend Git revision.
- Production PocketBase version.
- Existing-user identity continuity.
- Collection authorization.
- Backup retention and isolated restoration.
- Account deletion and provider revocation.

The app supports native email/password registration and verification-email
requests through the pinned PocketBase contract. Password-reset confirmation
and email-verification confirmation remain blocked until the backend defines and
ships an Associated Domains file, stable HTTPS universal-link routes, the exact
token path/query format, and safe fallback behavior for older app versions and
the web app. Only then should the iOS app add the matching Associated Domains
entitlement, route those links to native token confirmation screens, and verify
expired, reused, malformed, and cross-environment tokens.

Account deletion is a backend-first App Store release blocker. The existing web
flow lets the client write its own audit record and then delete the user, so the
iOS app must not reuse it. The backend must add one authenticated deletion
endpoint or hook that derives the user ID, email, signup method, timestamp, and
usage snapshot from the authenticated server context; writes an immutable audit
record that clients cannot create or change; deletes the account and owned data
with defined all-or-nothing or retry-safe behavior; revokes active sessions and
OAuth grants; returns only a completion result; and has cross-client tests for
authorization, cascades, partial failure, retries, and older web/iOS clients.
After that backend revision is deployed and pinned, the app must add a clear
in-app deletion action with confirmation and reauthentication where required.

Privacy Policy and Terms use the live public web pages. Support and account-
deletion help use `support@organizedglitter.app`; support contact is not a
substitute for the required in-app deletion flow.
