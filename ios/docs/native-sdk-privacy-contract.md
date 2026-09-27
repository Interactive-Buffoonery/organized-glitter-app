# Native SDK privacy contract (INT-1155)

Status: draft implementation contract for INT-1157 and INT-1158. The live
vendor settings and network checks below remain release gates. This document
covers PostHog product analytics and RevenueCat purchase processing. It does
not install either SDK. It extends the web
[`docs/analytics/posthog.md`](https://github.com/Interactive-Buffoonery/organized-glitter/blob/dev/docs/analytics/posthog.md)
rules and the accepted
[tips-first ADR](https://github.com/Interactive-Buffoonery/organized-glitter/blob/dev/docs/adr/0022-free-catalog-and-optional-tips.md).

## Product decision

Collect every meaningful native action and outcome in PostHog, without sending
user-entered content. Product analytics starts on by default, is explained in
the public privacy policy and Account settings, and has an in-app opt-out.
Purchase processing remains available when analytics is off. A second analytics
level requires a separate, named need; it is not part of the initial release.

Use **pseudonymous** in internal documentation. Sarah chose to join PostHog
events across a person's devices and support account-data deletion. Identify
signed-in events with the stable opaque PocketBase account ID, without sending
email or display name. Disclose that usage history is linked to the account;
do not describe it as anonymous. The final public wording and App Store answers
must reflect captured payloads.

## Boundary and data flow

```text
native action -> typed event + bounded properties -> analytics preference
              -> PostHog queue -> PostHog project

StoreKit purchase -> RevenueCat SDK -> RevenueCat project
                                   -> purchase result -> safe PostHog event

PocketBase session -> analytics identity/reset and RevenueCat billing identity
```

PocketBase remains the app and account backend. PostHog is diagnostic, not a
source of purchase, entitlement, or account truth. RevenueCat-to-PostHog
automatic forwarding stays off. Do not copy receipts, transaction IDs, vendor
customer IDs, or payment details into PostHog. SDK failure cannot prevent sign-in,
craft tracking, tipping, or purchase recovery.

## Reviewed SDK candidates and inventory

The source review used PostHog iOS [3.85.0](https://github.com/PostHog/posthog-ios/tree/3.85.0)
and RevenueCat Purchases iOS [5.91.0](https://github.com/RevenueCat/purchases-ios/tree/5.91.0).
These are audit candidates, not yet package pins in `ios/project.yml`. Re-run
the audit if implementation selects different versions.

| Path | Data and identifiers | Local storage | Recipient and purpose |
| --- | --- | --- | --- |
| PostHog explicit events | Event name, timestamp, distinct and session IDs, safe app-provided properties; the SDK also adds app version/build, bundle ID, device model/type, OS, screen size, locale, time zone, network type, and SDK version. | Identity and file-backed event queue in app Application Support; SDK default queue cap is 1,000 events on iOS. | Configured PostHog project for product analytics. Confirm actual endpoint and automatic/server-added fields from network captures. |
| PostHog optional SDK paths | Lifecycle and screen events default on; surveys and feature flag preload default on. UIKit/SwiftUI element autocapture, replay, and crash autocapture default off. Screen calls can stamp later events with a screen name. | Feature-flag, replay, log, and event storage may be created during setup. | PostHog; disable unused automatic paths explicitly and inspect setup traffic. |
| RevenueCat purchases | App User ID, purchase/receipt history, product and transaction data needed for StoreKit processing. Anonymous mode generates a cached App User ID; a custom ID can connect purchases across devices. | SDK caches customer and purchase state and, in anonymous mode, its generated ID. This is billing state, not an app record cache. | RevenueCat and Apple for purchases, reporting, and recovery. |
| RevenueCat attribution/diagnostics | SDK diagnostics default off. Automatic device-identifier collection is enabled by default but its source documentation says identifier collection is conditional on attribution-network IDs being set. | SDK-managed cache. | RevenueCat and any enabled attribution destination. Do not configure attribution integrations; explicitly disable automatic device-identifier collection unless a purchase requirement proves it necessary. |

PostHog 3.85.0's `remoteConfig` property is a deprecated no-op: the reviewed
source says remote configuration now always loads. Turning feature-flag preload
off does not prove that setup makes no flag/config request. Capture setup
traffic with both analytics states and document any request before shipment.

The [PostHog manifest at 3.85.0](https://github.com/PostHog/posthog-ios/blob/3.85.0/PostHog/Resources/PrivacyInfo.xcprivacy)
declares Product Interaction and Other Usage Data for analytics, plus
UserDefaults, System Boot Time, and File Timestamp accessed APIs. The
[RevenueCat manifest at 5.91.0](https://github.com/RevenueCat/purchases-ios/blob/5.91.0/Sources/PrivacyInfo.xcprivacy)
declares Purchase History for app functionality and UserDefaults access. Both
mark their declared collected data as not linked and not used for tracking;
that does not determine the app's final disclosures if the app supplies a
stable account ID or joins data elsewhere. INT-1160 must inspect the assembled
binary's privacy report and the actual configuration.

## Analytics behavior

- Use an explicit native event registry with snake_case names. Capture confirmed
  outcomes after successful writes. For an uncertain write, refresh before
  recording success. Capture screen and action events deliberately instead of
  relying on autocapture.
- Cover entry, authentication, navigation, library open/search/filter/sort,
  create/edit/delete, progress, photos added, randomizer, support, tip attempt
  and outcome, purchase recovery, and meaningful failures. Use fixed enums for
  surface, craft, operation, outcome, and provider; booleans, bounded counts,
  duration buckets, and app version are allowed. Reuse a web event name only
  when the native action has the same meaning.
- Do not send names, titles, notes, descriptions, search queries, raw barcodes,
  images, private file URLs, filenames, full routes/URLs, email, display name,
  auth values, raw errors, payment details, or PocketBase record IDs as event
  properties. A search action can include a query-length bucket and result-count
  bucket. A photo action can include an outcome and count, never image metadata.
- Disable lifecycle and screen auto-events, element autocapture, replay, crash
  autocapture, automatic logs, surveys, feature-flag preload, push collection,
  and unused tracing. Do not call manual screen APIs with dynamic titles. Review
  the SDK's automatic properties and use its `beforeSend` hook as a final
  allowlist, then verify the serialized network body.
- Separate production and nonproduction PostHog projects or disable collection
  in local/UI tests. Do not send fixtures to production.

The initial native event allowlist is below. INT-1158 should add the names to
one Swift enum and reject any event outside it. Add a name or property only
after documenting the product question and checking its serialized payload.
Each event may also carry fixed `platform`, `environment`, and app-version
fields. SDK-added fields still need network review.

| Allowed event names | Trigger | App-provided properties |
| --- | --- | --- |
| `app_opened`, `screen_viewed` | App becomes usable; a named native screen appears | Fixed screen and entrypoint enums |
| `registration_started`, `auth_login_succeeded`, `auth_registration_succeeded`, `auth_logout_completed` | Confirmed auth transition; do not count silent restore as a login | Method, provider, and entrypoint enums |
| `library_search_performed`, `library_filter_changed`, `library_sort_changed`, `library_item_opened` | User acts in the library | Craft, filter, sort, and item-type enums; query-length and result-count buckets |
| `project_created`, `project_updated`, `project_archived`, `project_deleted`, `project_status_changed` | Confirmed diamond-project write | Surface, status, and operation enums; count bucket if relevant |
| `coloring_book_created`, `coloring_book_updated`, `coloring_book_deleted`, `coloring_book_status_changed`, `coloring_page_status_changed` | Confirmed coloring write | Surface, status, and operation enums |
| `progress_note_added`, `coloring_page_progress_note_added`, `coloring_page_progress_note_updated`, `coloring_page_progress_note_deleted`, `photo_added`, `coloring_page_photo_added`, `coloring_page_photo_deleted` | Confirmed note or photo write | Craft and surface enums; count bucket only |
| `randomizer_spin`, `overview_craft_filter_changed`, `overview_sort_changed`, `vertical_preferences_updated` | Confirmed interaction or preference change | Fixed mode, craft, sort, or preference enums |
| `first_project_created`, `first_coloring_book_created`, `first_progress_note_added`, `first_photo_added`, `randomizer_first_spin`, `activation_completed` | Once-only funnel milestone after confirmed action | Craft enum, bounded created-item count, and qualifying-action booleans |
| `support_screen_viewed`, `tip_purchase_outcome`, `purchase_restore_outcome` | Support view or terminal StoreKit/RevenueCat result | Fixed surface, public tip tier, and outcome enums; duration bucket |
| `operation_failed` | User-visible, actionable failure | Fixed operation and failure-category enums; no raw error text or request data |

Do not add event names for user-entered taxonomy, project subjects, or search
terms. A safe event records that an action happened and its outcome, not the
private content involved. New native screens and actions should extend the
registry as they ship, with this table reviewed at the same time.

### Preference and account transitions

The Account control says that turning analytics off stops *new usage
collection*. It must prevent new captures immediately, including SDK automatic
events. Keep the device preference independent of the PocketBase server record
and load it before initializing the SDK. Before sign-in, capture allowed entry
events under the SDK's generated ID. After successful sign-in or restoration,
identify with the PocketBase account ID so the person's native events can be
joined across devices and located for erasure. On sign-out, invalid session,
deletion, or account switch, reset identity before capturing another account's
actions. Do not call `identify` or capture account-linked events while opted
out. No email or display name is supplied to either SDK. The identity is
linked to the app account, so the public policy and App Store answers must say
so.

PostHog 3.85.0's [`optOut()`](https://github.com/PostHog/posthog-ios/blob/3.85.0/PostHog/PostHogSDK.swift)
ignores future captures but does not call its queue's `clear()` method.
[`reset()`](https://github.com/PostHog/posthog-ios/blob/3.85.0/PostHog/PostHogStorage.swift)
clears identity state and explicitly preserves current queue files; `flush()`
has no opt-out check in the reviewed source. Thus a previous event may still be
delivered after a preference change or account switch, with its original event
identity. Do not promise that opt-out deletes past events or stops delivery of
already collected events. Verify this behavior in a network harness and choose
a supported queue policy before INT-1157 ships user-facing copy. Account data
erasure is a separate request handled under INT-1159.

## Billing behavior

Tips are optional, repeatable one-time purchases with no feature entitlement.
RevenueCat is required for this purchase path and is unaffected by the
analytics preference. Use a stable opaque PocketBase account ID as RevenueCat's
custom App User ID for signed-in purchases. Its
[restore guidance](https://www.revenuecat.com/docs/getting-started/restoring-purchases)
says consumable purchase history is recoverable across devices through a custom
App User ID; an anonymous device ID does not provide that continuity. Never
send email or display name as the billing ID or subscriber attributes.
RevenueCat's [identity guidance](https://www.revenuecat.com/docs/customers/identifying-customers)
describes `logIn`, `logOut`, and aliases. INT-1156 must test same-device account
switching and restore behavior without client-side account merging. Record the
RevenueCat project's restore and integration settings; SDK defaults alone do
not establish them.

## Retention, deletion, and release evidence

PostHog's [event retention](https://posthog.com/docs/api/events-retention)
depends on the project plan and must be read from the live project. Its
[person deletion](https://posthog.com/docs/data/persons) can remove events for
the known PocketBase account distinct ID. RevenueCat provides
[customer deletion](https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile)
through its dashboard/API. INT-1159 must specify when the backend requests
both vendor deletions, how failed requests are retried, and how any pre-sign-in
anonymous events that never joined an account are handled. Do not claim that
deleting a PocketBase account alone deletes vendor data.

Before INT-1157 and INT-1158 are privacy-complete:

1. Pin the actual SDK versions and compare their source, manifests, and defaults
   with this table. Inspect live PostHog retention, RevenueCat restore behavior,
   attribution destinations, and vendor deletion settings.
2. In an isolated iOS 26 simulator harness, inspect actual requests on fresh
   install, default-on use, opt-out, relaunch, opt back in, offline/reconnect,
   logout, second-account login, and purchase/restore. Assert event names and
   property allowlists; inspect automatic, queued, and server-enriched fields.
3. Verify the account identification and queued-event behavior, then document
   exact Account setting and privacy-policy text. Verify that the UI wording
   matches observed opt-out behavior, and that analytics failure never blocks
   product flows.
4. INT-1160 reviews the assembled privacy report and App Store labels against
   the shipped binary and live network behavior. Keep screenshots and packet
   evidence free of user content and credentials.

## Handoff

- **INT-1157:** Implement the preference and policy disclosure using the
  verified identity and queue decisions; keep billing processing separate.
- **INT-1158:** Implement broad explicit event coverage and wire-payload tests.
  Reconcile its earlier draft plan's small event set and unspecified account
  identity with this contract's broad coverage and signed-in opaque ID.
- **INT-1159:** Integrate PostHog and RevenueCat erasure with account deletion.
- **INT-1160:** Verify final package manifests, app privacy report, and App
  Store disclosures from the shipped configuration.
