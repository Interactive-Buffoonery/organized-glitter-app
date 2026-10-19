# Native account deletion failure model

The backend and account scope, session generation, proof and stage travel
through one coordinator. Tests precede implementation on 2026-10-18.

- Store failure before submission: send no deletion; preserve all local edits.
- Lost response, cancellation after dispatch, malformed 200 or unknown-proof
  401: keep the submitted intent and lock access. Never infer either deletion
  or an intact account. Retry only the same proof without a token.
- Restart: read Keychain before login restoration. Submitted intents block login;
  confirmed intents automatically resume idempotent local removal. Prepared
  intents can cancel before backend or account matching because nothing was sent.
- No-dispatch submitted request: an unknown-proof 401 remains uncertain. After
  fresh verification of the original account with the same proof, a separate
  confirmation can retry the guarded request with its retained session. No
  session refresh or automatic POST replay is allowed.
- Wrong identity or changed session at any suspension: reject fresh auth and
  never publish success or clean a different account. Step-up tokens are discarded.
- Confirmation: require verified existing identity, a proof less than five
  minutes old and explicit destructive confirmation including pending edits.
- Local cleanup failure: retain confirmed intent plus existing removal markers;
  retry cleanup without another destructive request. Clear intent last.
- Analytics: disable forwarding before closing SDK; remove only audited SDK
  files, including disk queues. No flush. Reinitialization must never resend
  the deleted account's events or remove unrelated Application Support files.
- Explicit signed-out local removal: a failed analytics purge leaves removal
  markers in place. Restoration retries the purge before clearing markers or
  offering sign-in.
- Ordinary expiry: preserve pending edits and downloaded records. A 401 is not
  a remote-deletion signal. Explicit sign-out removal remains a user choice.

Production backend revision, provider revocation, vendor erasure, backup
retention and remote-device deletion signalling require separate evidence.
