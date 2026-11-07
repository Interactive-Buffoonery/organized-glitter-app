# Pinned T3 compatibility

Inspected installed `ManagedEndpointRuntime-mwyO39Ge.mjs`, protocol 2,
T3 `0.1.8-nightly.20261104.4179`. This is source correspondence, not a live RPC test.

| Operation | Required fields in installed schema | Adapted client |
| --- | --- | --- |
| `message.dispatch` | commandId, threadId, messageId, text, attachments, dispatchMode | Delivery.turnCommand supplies these; CommandIdentity stamps commandId. dispatchMode is `{type: start_immediately}`; deliveryIntent `auto` is supported. Gateway strips optional modelSelection/runtimeMode before sending. |
| `run.interrupt` | commandId, threadId, runId | SquircleModel.stop uses current activeRunID; command identity is stamped by command reducer. No interrupt without a known run. |
| `runtime-request.respond` | commandId, threadId, requestId | Explicit answers or decision only. Installed decisions include accept, acceptForSession, acceptAlways, decline, cancel; no automatic answer added. answers is a string-keyed record of unknown values. |
| `assets.persistChatAttachments` | threadId, messageId, attachments | Gateway uploads image dataUrl/name/mimeType/sizeBytes before dispatch; returned persisted attachments replace uploads. Installed result is `{attachments: ChatAttachment[]}`. |

The policy boundary limits those three mutation commands to the pinned thread.
Both allowlisted project cards deliberately open that same thread, including
when Squircle's agent directory and imported app metadata are empty. The shell
must still contain those existing nondeleted projects. No catalog import or
service enrollment mutation is needed to populate them.

`check-sql.py CHECKOUT DATABASE` expands the upstream Rust SQL macros and prepares
all 19 constants using EXPLAIN against a read-only connection. It does not execute
queries against user rows. With no database argument it runs a sanitized upstream
fixture in memory and drops the three legacy tables before testing message,
image, thread/project isolation and literal search behavior. The pinned adapter
reads V2 only: it intentionally does not retrieve old migration-only history.

Rust policy tests cover the complete configuration/export-method/disable matrix
and approval-required defaults while preserving explicitly requested modes.
They are added to the upstream harness but require a completed gated cargo test.
Neither SQL preparation nor fixture execution proves live subscriptions,
reconnection, provider approval behavior or screenshot upload.
