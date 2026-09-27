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

The approved offline-library design intentionally supersedes the earlier
in-memory-only policy. This layer adds account- and backend-scoped SwiftData
storage for downloaded records and pending existing-record metadata/status
edits. PocketBase remains authoritative for shared data and authorization.
The follow-up integration connects feature views, offline session restoration,
and bounded private artwork caching. It must preserve pending work across
authentication/download failures and confirm discarding it during sign-out.
Creates, deletes, notes, uploads, taxonomy, account settings, and book page-count
changes remain online-only.

Until that integration lands, the active feature behavior remains:

- PocketBase is the only identity system and backend.
- Credentials are stored in Keychain.
- Records remain in memory for the process lifetime.
- Writes require connectivity.
- The app does not queue writes or claim realtime synchronization.
- Concurrent edits use PocketBase last-write-wins behavior.
- A write with unknown completion must be refreshed before retry.
- Library search, status filters, sorting, and pagination execute on PocketBase.
- File images use short-lived PocketBase file tokens fetched for the signed-in
  account. The app renews the token shortly before its expiry while its signed-in
  shell is visible, with a 30-second minimum delay between renewals. A missing
  token suppresses image requests. `RemoteArtwork` uses token-bearing URLs for
  downloads but excludes the token query item from its in-memory cache and
  in-flight request keys; thumbnail parameters remain part of those keys. The
  cache is purged on session changes. All file URL construction goes through
  `PocketBaseClient.fileURL`.

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

The source includes native email/password registration, verification-email
requests, and password-reset confirmation. Password reset uses the canonical
HTTPS route documented in `password-reset-links.md` and keeps the web route as
the fallback when the app is not installed. The native code and Associated
Domains entitlement are preparatory until the matching AASA file is deployed
and verified. Do not update `BackendContract.json` or claim production link
handling before that deployed revision is known. Email-verification
confirmation remains blocked on its own universal-link contract.

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
