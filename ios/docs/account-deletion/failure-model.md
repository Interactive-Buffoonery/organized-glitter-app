# Native account deletion failure model

The backend and account scope, session generation, proof and stage travel
through one coordinator. Tests precede implementation on 2026-10-18.

- Store failure before submission: send no deletion; preserve all local edits.
- Lost response, cancellation after dispatch, malformed 200 or unknown-proof
  401: keep the submitted intent and lock access. Never infer either deletion
  or an intact account. Retry only the same proof without a token.
- Restart: read Keychain before login restoration. Submitted intents block login;
  confirmed intents resume idempotent local removal. Prepared intents can cancel.
- Wrong identity or changed session at any suspension: reject fresh auth and
  never publish success or clean a different account. Step-up tokens are discarded.
- Confirmation: require verified existing identity, a proof less than five
  minutes old and explicit destructive confirmation including pending edits.
- Local cleanup failure: retain confirmed intent plus existing removal markers;
  retry cleanup without another destructive request. Clear intent last.
- Analytics: disable forwarding before closing SDK; remove only audited SDK
  files, including disk queues. No flush. Reinitialization must never resend
  the deleted account's events or remove unrelated Application Support files.
- Ordinary expiry: preserve pending edits and downloaded records. A 401 is not
  a remote-deletion signal. Explicit sign-out removal remains a user choice.

Production backend revision, provider revocation, vendor erasure, backup
retention and remote-device deletion signalling require separate evidence.
