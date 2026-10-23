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
`Interactive-Buffoonery/organized-glitter-web`.

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

## Randomizer history

The Classic Randomizer selects from a frozen, account-owned library pool with
an equal chance for every selected item. Repeats are allowed. Skipping the
animation reveals the same winner; it does not create another draw.

`LibrarySession` reads the existing PocketBase `randomizer_spins` collection
and records completed draws online. The initial history read requests eight
recent rows; Show More History requests up to fifty. History remains separate
from filter and result state, and navigation rechecks the current owned library.
Legacy or malformed optional metadata falls back to the saved top-level fields.

Each frozen draw dispatches at most one creation in the app session. There is
no backend idempotency key, offline queue, or automatic POST retry after an
ambiguous outcome. Spin creation explicitly disables the transport's authentication
refresh-and-replay behavior; terminal authentication recovery runs after write
accounting unwinds. Other creates and GET requests retain their existing refresh
policy. GET refreshes can reconcile history without repeating a creation. Accepted creates trigger a bounded GET refresh at the current eight/fifty-row
limit so other clients’ history appears. Acknowledged saves remain acknowledged
if that read fails. The immediate refresh preserves its acknowledged row and
reads retain concurrent acknowledgements; later reads remain authoritative. Terminal history auth
failures use session recovery after write accounting unwinds, preserving pending
library edits.
Failed and uncertain local draws retain their frozen item title and existing failure
message alongside history when a later draw replaces the result. The current result
shows its own message once; failure announcements are tracked once per draw while
the page is visible. Uncertain draws offer GET-only history refresh and never
replay creation. These local receipts and titles clear on account close.
History is held in account-scoped session memory and clears when that session
closes; the downloaded SwiftData library does not include spin history.

## Analytics consent

The shared `users.analytics_opt_out` account setting remains online-only. A
separate device-local pause stops collection and new batch requests immediately,
even offline, without changing or queuing the account setting. This pause lasts
for the signed-in app session; account refreshes cannot clear it. A confirmed
online analytics save can clear it, unless the user paused again during that save.
Restarting the app or signing out ends the session pause. Previously collected
events are not deleted, and requests already in flight may finish.

Connected foreground clients with configured, enabled collection refresh consent
every 30 seconds so opt-outs from another device propagate while the app stays
open. Successful refreshes apply the server choice without first cycling SDK
consent. Failed or unreadable refreshes pause collection. Paused, opted-out,
unconfigured, offline, and inactive clients do not poll. Scene activation,
reconnection, Account refresh, and preference writes still reload account state;
remote opt-in is picked up at those refresh points.

## Free native app

All native features are free. Voluntary website support grants no app features,
content, or account privileges. The app contains no payment processing,
contribution prompts, checkout links, or payment-dependent access.

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

- The app price is free and submitted metadata matches the free product.

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

The native account-deletion flow uses the guarded backend contract in
[`account-deletion/contract.md`](account-deletion/contract.md). Account settings
opens a native deletion screen. A verified existing password, Apple, Google or
Discord identity must authorize a new proof before a separate destructive
confirmation. Step-up responses never replace the app session or link accounts.
The Keychain intent is scoped to backend and account and is saved before
verification and again before the destructive request. Ambiguous outcomes lock
account access and retain local edits. Recovery precedes session restoration.

A validated deletion response starts durable local removal using the existing
library markers. Credentials, library records and pending edits, artwork,
in-memory caches and the audited PostHog SDK disk queues are removed. Local
cleanup and vendor cleanup are separate states. A server receipt with pending
vendor cleanup is never presented as vendor erasure. The native backend pin
remains unchanged until the deployed contract is verified.

A normal authentication failure preserves downloaded libraries and pending
edits. The backend has no trustworthy remote-deletion signal for other devices;
401 alone never proves deletion. The signed-out screen offers explicit,
confirmed device-only removal of retained libraries for the configured server.
It also offers sign-in to recover access. This action uses removal markers and
never calls server deletion. It cannot resolve a submitted deletion intent;
that flow stays locked until a valid same-proof receipt confirms deletion.

Privacy Policy and Terms use the live public web pages. Support uses
`support@organizedglitter.app`; account-deletion support is recovery help after
an unresolved result, rather than the normal in-app deletion route.
