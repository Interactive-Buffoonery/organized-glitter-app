# Native architecture

The app supports iPhone and iPad from iOS and iPadOS 26.0. APIs introduced
after iOS 26 require availability checks.

## Boundaries

- `OrganizedGlitter/App` owns configuration, session state, and root navigation.
- `OrganizedGlitter/Networking` owns concrete PocketBase requests.
- `OrganizedGlitter/LocalLibrary` owns durable records, queued edits, and sync.
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
- The account-scoped SwiftData library and bounded private artwork cache
  intentionally supersede the earlier in-memory-only client policy. SwiftData
  contains downloaded records and pending supported edits; PocketBase remains
  authoritative for shared data and authorization.
- Library reads and writes flow through the account-scoped `LibrarySession`.
- SwiftData stores downloaded records, the last verified user, and pending
  metadata edits. CloudKit synchronization is explicitly disabled.
- Local saves commit the displayed change and retry operation together before
  the editor reports success. Unacknowledged operations retain stable IDs.
- A complete PocketBase snapshot replaces confirmed server state; failed
  snapshots never imply deletion. Pending changes remain an overlay.
- The mobile apply route checks ownership, changed fields, and related lifecycle
  fields atomically. Conflicts preserve local edits for explicit resolution.
- Creation, deletion, uploads, taxonomy, account preferences, and book page-count
  changes remain online operations. Server hooks continue to own page generation.
- Local data is separated by backend and user ID, protected by Apple file
  protection, and excluded from device backups. Unsent edits exist only on this
  device until synchronized; uninstalling the app removes them.
- Explicit sign-out requires confirmation before discarding pending changes and
  removes the local account library and downloaded artwork. Authentication
  failure locks the account without deleting unsent work.
- Artwork is stored in a bounded, account-scoped cache without token-bearing
  URLs. Cache-only URLs cannot trigger network downloads. Online file requests
  require a file token and the configured backend origin. Successful snapshots
  prune files no longer referenced by the accessible library.

See [the offline library contract](offline-library.md) for rollout and tests.

## Dependency policy

Use SwiftUI, Observation, URLSession, AuthenticationServices, Keychain
Services, PhotosPicker, OSLog, XCTest, and Swift Testing before adding a
dependency. Add a dependency only for a demonstrated platform gap.

## Release gates

`BackendContract.json` records a pinned backend commit, PocketBase version, and
schema hash. The current unit test checks that these fields are populated and
have expected lengths; it does not verify the referenced source, runtime
compatibility, or which revision is deployed to production. There is currently
no automated source contract verification workflow in this repository.

Before App Store submission, the release owner must separately verify:

- The submitted build, App Store compatibility metadata, and release notes all
  state iOS and iPadOS 26.0 as the minimum.
- Deployed backend Git revision.
- Production PocketBase version.
- Account isolation and offline session restoration.
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
