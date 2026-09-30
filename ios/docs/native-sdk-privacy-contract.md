# Native SDK privacy contract (INT-1155)

Status: implementation requirements for native analytics and purchase processing.
No SDK is installed by this document. Integration and release evidence remain
open until verified against the selected packages and shipped configuration.

This contract extends the web [analytics rules](https://github.com/Interactive-Buffoonery/organized-glitter/blob/dev/docs/analytics/posthog.md)
and the accepted [tips-first ADR](https://github.com/Interactive-Buffoonery/organized-glitter/blob/dev/docs/adr/0022-free-catalog-and-optional-tips.md).
Dated SDK research and planning handoffs live in Sarah's vault at
`Coding Projects/OrganizedGlitter/Planning/Research/2026-09-27-native-sdk-source-audit.md`.
The requirements below are self-contained; the vault is not needed to implement
them. Recheck upstream behavior when selecting or upgrading SDK versions.

## Product and identity rules

- Capture every meaningful native action and outcome without user-entered
  content. Analytics starts on by default, has a clear Account opt-out, and is
  disclosed in the public privacy policy. No second analytics level is planned.
- Usage history is pseudonymous and linked to the account, not anonymous. Use
  the stable opaque PocketBase account ID to join signed-in events across
  devices and locate vendor data for deletion. Send no email or display name.
- PocketBase remains the only account and library backend. PostHog is not a
  source of purchase, entitlement, or account truth.
- Optional, repeatable one-time tips grant no feature entitlement. RevenueCat
  purchase processing remains available when analytics is off. Analytics failure
  must not block product flows; purchase failure must preserve retry/recovery
  without claiming success or disabling unrelated sign-in and crafting.
- Keep automatic RevenueCat-to-PostHog forwarding and attribution integrations
  off. Never send receipts, transaction IDs, vendor customer IDs, payment
  details, or subscriber email/name into analytics.

## Event and property boundary

Use one typed native event registry with snake_case names. Reuse a web name
only when the action has the same meaning. The table is a contract for coverage,
not a claim that every listed feature currently exists. Add events as their
reachable actions ship; do not create placeholders or synthetic activity.

| Coverage | Allowed names | Trigger and bounded properties |
| --- | --- | --- |
| Entry and authentication | `app_opened`, `screen_viewed`, `registration_started`, `auth_login_succeeded`, `auth_registration_succeeded`, `auth_logout_completed` | Usable app, fixed screen or explicit auth transition; screen, entrypoint, method and provider enums. Silent restoration is not a new login. |
| Library and preferences | `library_search_performed`, `library_filter_changed`, `library_sort_changed`, `library_item_opened`, `vertical_preferences_updated` | User interaction or confirmed preference change; craft, item type, filter/sort enums, query-length/result-count buckets. |
| Diamond records | `project_created`, `project_updated`, `project_archived`, `project_deleted`, `project_status_changed` | Confirmed write; fixed surface, status, operation and write-state enums. |
| Coloring records | `coloring_book_created`, `coloring_book_updated`, `coloring_book_deleted`, `coloring_book_status_changed`, `coloring_page_status_changed` | Confirmed write; fixed surface, status, operation and write-state enums. |
| Progress and photos | `progress_note_added`, `coloring_page_progress_note_added`, `coloring_page_progress_note_updated`, `coloring_page_progress_note_deleted`, `photo_added`, `coloring_page_photo_added`, `coloring_page_photo_deleted` | Confirmed note/photo action; craft/surface enums and count bucket. Diamond note edit/delete and other implemented actions must receive documented registry entries during integration. |
| Activation | `first_project_created`, `first_coloring_book_created`, `first_progress_note_added`, `first_photo_added`, `randomizer_first_spin`, `activation_completed` | Once-only confirmed milestone; craft enum, bounded count and qualifying-action booleans. Future actions have no milestone until implemented. |
| Support and billing | `support_screen_viewed`, `tip_purchase_outcome`, `purchase_restore_outcome` | Reachable screen or terminal purchase/recovery result; surface, public tip tier, outcome and duration bucket. |
| Failures | `operation_failed` | Actionable user-visible failure; fixed operation and failure-category enums, never raw errors. |
| Future or changed surfaces | `randomizer_spin`, `overview_craft_filter_changed`, `overview_sort_changed` | Only when the corresponding action exists; fixed mode/craft/sort enums. Current Home/Library/Search navigation does not imply a reachable Randomizer or Overview filter control. |

The registry must also cover current Home logging, Notes navigation/filters,
note edits/deletes, photo viewing, Account actions and sync/conflict decisions.
Document each additional name, trigger and allowed properties before wiring it.
Do not treat the original web-derived list as a smaller approved native scope.

- Allow fixed enums, booleans, bounded counts, duration buckets, platform,
  environment and app version. Review SDK-added fields separately.
- Block names, titles, notes, descriptions, search text, raw barcodes, images,
  private file URLs, filenames, full routes/URLs, email, display name, auth
  values, raw errors, payment details and library record IDs. The account ID
  is the approved identity, not an arbitrary event property.
- Apply a final property allowlist using supported SDK controls, then test the
  serialized wire body. Search carries length/result buckets; photos carry
  outcomes/counts, never image metadata.
- Disable automatic lifecycle/screen events, element autocapture, replay,
  crash autocapture, automatic logs, surveys, feature-flag preload, push
  collection and unused tracing. Verify setup traffic; disabling a named
  option is not evidence that all automatic requests stopped.
- Use the shared production analytics project for web/native with a fixed
  platform property. Isolate nonproduction traffic or disable collection in
  local/UI tests; never send fixtures to production.

## Saves, preference and account transitions

- Capture outcomes after the relevant save is confirmed. Native existing-record
  edits may be committed locally before server acceptance: distinguish durable
  local save from synchronized success with a fixed write-state enum. Do not
  report a pending/conflicted edit as accepted by the server or double-count
  its user action when synchronization retries. For uncertain online writes,
  refresh before reporting success.
- Store the device analytics preference independently of PocketBase and load
  it before SDK initialization. Opt-out must immediately prevent new captures,
  including automatic events. Do not identify an account while opted out.
- Before sign-in, permitted entry events may use the SDK-generated identity.
  After successful sign-in/restoration, identify using the opaque account ID.
  Reset identity before another account's activity on sign-out, invalid session,
  deletion or switch. No email or display name is supplied to either SDK.
- Account wording must explain that opt-out stops new usage collection. The
  September 27 source audit found queue preservation in PostHog 3.85.0; identity
  reset and opt-out must not be assumed to erase queued events. Verify the
  selected version's delivery behavior and choose a supported queue policy.
  Do not promise deletion of past events or cessation of already-collected
  event delivery without wire evidence. Account erasure is a separate request.

## Purchase identity and erasure

Use the opaque PocketBase account ID as the RevenueCat custom App User ID for
signed-in purchases. Verify login/logout, same-device account switching and
purchase recovery for the selected consumable products and project settings.
Do not merge app accounts on the client, grant tip entitlements, or describe
recovery as restoring a consumed tip's feature access. Disable automatic
device-identifier collection unless a documented purchase requirement proves
it necessary; verify actual attribution and diagnostic traffic.

Account deletion must include a backend-owned vendor-erasure handoff: identify
the vendor data to remove, request deletion, retry failures, and define handling
for pre-sign-in events not joined to an account. Deleting PocketBase alone is
not proof of vendor erasure. Record live retention and deletion settings in
private release evidence rather than copying mutable vendor settings here.

## Integration and release checklist

Each owner records evidence against the exact package versions and build. This
checklist replaces separate release and handoff lists; unverified gates are not
claims that an SDK or vendor project is absent.

| Owner | Required evidence |
| --- | --- |
| INT-1158 — analytics integration | Pin selected SDK version; compare source/defaults/manifests; implement typed events and final property allowlists. Cover current reachable actions and distinguish local saves from sync acceptance. |
| INT-1158 — network validation | Isolated iOS 26 harness: fresh install, default-on/off startup, opt-out, relaunch, opt back in, offline/reconnect, logout, second-account login and failed saves. Inspect setup, automatic, queued and server-enriched fields; assert identity and no private content. |
| INT-1157 — preference/disclosure | Verify immediate opt-out and account transitions; choose tested queue policy; match Account and public privacy copy to observed behavior. Verify analytics failure cannot block product flows. |
| INT-1154 / INT-1156 — purchases | Verify current Apple/RevenueCat provisioning, selected SDK, project restore/attribution settings, sandbox purchase/recovery payloads and account switching. Purchase setup does not block PostHog implementation. |
| INT-1159 — erasure | Backend vendor deletion, retry behavior, retention and unjoined pre-sign-in event handling; no claim that account deletion alone erases vendor history. |
| INT-1160 — submission | Assembled binary privacy report and App Store labels match actual account linkage, shipped configuration and network captures. Vendor manifests alone do not determine the app's disclosures. |

Keep screenshots and packet evidence free of user content, credentials and
private URLs. Dated source findings live in the vault; new version audits and
live setup evidence must be recorded there rather than asserted from old notes.
