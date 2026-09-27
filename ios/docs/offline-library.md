# Local library and PocketBase synchronization

## Scope

The native app reads projects, coloring books, coloring pages, and downloaded
progress notes from a private SwiftData store. Existing metadata and status
edits save locally, including while offline. PocketBase remains the only
backend and identity system. There is no CloudKit sync or guest account.

Creation, deletion, note submission, file uploads, taxonomy changes, account
settings, and changing a book's page count require a connection. The server
continues to generate coloring pages and maintain derived values. Online
changes pass through LibrarySession and update the local view after acceptance.
An accepted remote write must not be retried merely because a later local
refresh failed.

## Components

- `LocalLibraryStore`: actor-owned SwiftData context, explicit saves, account
  isolation, server snapshots, pending operations, and conflict resolution.
- `LocalSyncCoordinator`: download a complete snapshot, submit queued operations,
  then download authoritative results after submitted operations. Cancellation invalidates late responses.
- `LibrarySession`: observable feature boundary and session lifetime, local
  projections, online mutations, sync status, and user-facing conflict recovery.
- `PocketBaseClient`: concrete authenticated HTTP transport. The same transport
  handles refresh and errors for ordinary and mobile sync requests.
- `PrivateArtworkStore`: bounded downloaded artwork, separate from unsent work.

## Persistence and privacy

The database is under Application Support and disables CloudKit explicitly.
Its directory uses Apple file protection and is excluded from device backups.
Each record, note, and saved identity is scoped by backend URL and account ID.
Credentials remain in Keychain. No user content, tokens, or private URLs enter
logs. Downloaded artwork uses hashed names in account-separated cache folders,
complete file protection, and a 128 MiB limit per account. Cache eviction cannot
remove pending edits. Previously viewed artwork may be evicted and unavailable
offline. Token rotation does not change the cache key.

The first sign-in requires connectivity. A previously verified account can open
its local library if connectivity is unavailable. A confirmed authentication
rejection locks the library and preserves pending edits for signing back into
that same account. Remote revocation cannot be discovered while offline.
Explicit sign-out pauses new edits, checks pending work, requires an explicit
discard decision when needed, and removes local account data. A durable cleanup
marker survives interruption; startup completes removal before opening any account.
Sign-in stays unavailable until removal finishes, and account-setting saves are
drained before deletion. Losing or
uninstalling the app before synchronization can lose unsent changes.

## Wire contract

The backend owns `GET /api/mobile/sync/snapshot` and
`POST /api/mobile/sync/apply`. Its authoritative wire documentation is
`docs/pocketbase/mobile-sync.md` in the backend repository.

Snapshots include all supported records and owner-checked relation labels in
one transaction. They are complete or rejected, with a bound of 10,000 source
and related rows and 16 MiB. Only a complete, decoded, validated snapshot can
remove local records. There is no incremental cursor, timestamp pagination, or
realtime dependency in v1. This intentionally favors a straightforward
correctness contract for personal libraries; larger libraries require a
separately designed paginated snapshot contract.

Automatic edit sync coalesces nearby saves. Temporary failures retry queued work
with increasing delays from 30 seconds to five minutes while the app is running;
foreground entry and connectivity recovery also trigger sync. A cached response
never counts as an authoritative refresh when recovering an ambiguous online write.

Each edit contains a stable operation ID, target, partial patch, and original
values. The server compares those values in the same transaction as the write
and duplicate-operation receipt. Related lifecycle fields are checked as a
group. Changing another field can merge; changing the same field stops for
review. Client device clocks never decide which edit wins.

Pending changes survive restarts. A second edit made while the first is awaiting
confirmation must retain its own comparison baseline. An acknowledgment cannot
remove that newer edit. Deleted records retain unsent drafts for export and
explicit discard; they are never recreated automatically. Invalid operations
are parked for recovery rather than retried indefinitely.

## Release and verification

The backend migration and hooks must land and deploy before releasing this
native build. The native contract pins verified backend source and schema; it
does not establish deployment status. No production deployment is part of this
change. Backend and native PRs must be reviewed together before release.

Run `./ios/script/pre-pr.sh` with the iOS 26 simulator destination. Relevant
coverage includes durable restart, account isolation, follow-up edits, conflict
resolution, snapshot failure, local search and sorting, session expiration,
sign-out confirmation, and cache-only artwork requests. Backend tests run
against a disposable PocketBase instance with the production hooks loaded,
including unauthorized access, relation ownership, conflicts, replay, and
schema migration behavior. iOS 18 remains the deployment minimum.
