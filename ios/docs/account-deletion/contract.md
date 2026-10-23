# Native account deletion

This source implements the guarded backend contract. It does not establish
which backend revision is deployed. `ios/BackendContract.json` stays unchanged.
Backend schema, workers, retention and provider erasure remain owned by the web
repository.

## Authorization and transport

Account > Security > Delete Account requires an existing verified account.
Password authorization uses `/api/auth/step-up/password` with action
`delete_account`, target `account` and a private 32-random-byte base64url proof.
Apple uses fresh code and nonce with `deletionUserId` and `deletionProof` on
`/api/auth/apple/native`. Google and Discord use fresh OAuth credentials with
the guarded `og_step_up_*` createData fields. The server must reject a different
or unlinked identity without creating or linking an account. Native responses
are checked against the requested account; returned step-up tokens are discarded.

The proof and backend/account scope are saved to device-only Keychain before
verification. A separate final confirmation lists the pending-edit count and
requires a proof under five minutes old. The submitted stage is committed before
`POST /api/account/delete` sends exactly `{proof, confirmed: true}`. These POSTs
never use authentication-refresh replay. Session and account checks fence async
work. Locking drains and closes the LibrarySession before dispatch.

Only HTTP 200 with `status: deleted` and known `cleanup: pending | completed`
confirms deletion. A timeout, cancellation after dispatch, unknown-proof 401 or
malformed response leaves an uncertain, locked intent. Neither deletion nor an
intact account is inferred. Retries use the same proof with no auth token and
cannot authorize a new deletion. Receipt expiry can require support recovery.

The screen checks configured sign-in methods and the original account's connected
external identities before offering provider verification. A failed discovery
offers retry or support. If a submitted request never reached the server,
tokenless status checks remain uncertain. The user can separately verify the
original account again with the same proof, then explicitly confirm a guarded
retry using the retained original session. This does not open normal sign-in,
create or link an account, refresh the session, or infer anything from a 401.
An unavailable original session leaves recovery locked with a support route.

## Recovery and local removal

Keychain recovery runs before ordinary or fixture login restoration. Prepared
intents can be cancelled because no deletion was submitted. Submitted intents
show the locked recovery screen. Confirmed intents automatically retry only
local cleanup after a restart. An unreadable intent remains locked with retry
and support routes.
No other account can sign in during unresolved deletion or failed cleanup.

The confirmed stage is persisted before cleanup. Existing LocalLibraryStore
removal markers protect interrupted removal. Cleanup clears Keychain session
credentials, the scoped library and pending edits, scoped artwork, library and
artwork memory caches, and PostHog local state. The intent is cleared last.
Cleanup failure remains distinguishable from remote deletion failure.

A completed client receipt distinguishes server deletion, completed local
cleanup and pending/completed vendor cleanup. The server owns vendor status.
The app does not claim Apple/Google/Discord revocation, PostHog remote erasure,
backup expiration or restored-backup safeguards from a local test.

## PostHog 3.90.1 audit

The lock is version 3.90.1, revision
`4642df21b8f4d16dbffcdfe92dbfe97f80b946fc`. `PostHogStorage.swift` stores data in
Application Support / bundle identifier / project token. `reset()` and
`close()` deliberately retain current event/replay/log disk queues. The wrapper
first disables forwarding and cancels tracked forwarding requests, then opts
out and closes without flushing. Already transmitted requests cannot be undone.

`PostHogLocalStorage` removes only the audited StorageKey paths and survey lock
and revocation files in the SDK token directories and legacy bundle location.
It recognizes earlier `phc_` token directories even when current analytics is
unconfigured. Other files and directories remain. SDK queues are shared across
app accounts, so deletion drops all queued SDK events on this installation.
The real-SDK tests verify disk persistence after close, disk removal, no erasure
flush, no old-account delivery after reinitialization and unrelated-file survival.
Reaudit this allowlist and those tests when upgrading the SDK.

## Ordinary expiry and remote devices

Authentication expiry closes and locks access while preserving local edits.
401 cannot distinguish token expiry, remote deletion or another rejection. The
signed-out screen permits sign-in for recovery or an explicit confirmation to
remove retained libraries for this server from this device. It does not remove
other backend libraries or claim any server account status. Removal uses the
same durable markers and retries the audited PostHog disk purge before clearing
the final marker or allowing sign-in. This route is unavailable while a submitted deletion
intent is unresolved. Remote devices cannot automatically erase offline data;
a trustworthy server deletion signal is still a release gap.

## Validation boundaries

See `failure-model.md` and the private, gitignored local test evidence directory
`ios/.derived-data/deletion-evidence`. Focused fixture tests do not exercise live
provider reauthentication, backend transactions, vendor erasure or production.
Full iPhone/iPad pre-PR, guarded-backend integration, accessibility driving and
fresh independent implementation review remain separate release evidence.
