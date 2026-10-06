# Native analytics integration

This plan follows the free native app policy and the
[privacy contract](native-sdk-privacy-contract.md). The former plan on
`feature/int-1158` is superseded. Native payments, tip prompts and purchase
events are outside this work.

## Foundation

The first PR adds the pinned PostHog package, `NativeAnalytics`, a typed event
registry, a final payload allowlist, an Account preference and session identity
handling. It captures `app_opened` once after the signed-in account and its
analytics preference have been freshly verified. Restoration is not a new login.

`AppModel` supplies the opaque PocketBase account ID. Before switching an
identified account, or during sign-out, expiration and local cleanup, the
adapter closes its network gate and resets identity. Queued events retain the
identity recorded at capture. Account A is never identified directly as B.
New capture and batch requests stay suspended during restoration, sign-out
and cleanup. Cancelling a sign-out with pending edits restores the active
account identity.

The preference is stored on the PocketBase user record and defaults on. The same
choice applies on web and native clients. Native collection stays off until a
fresh authenticated response verifies the preference, so an offline cached
session never starts analytics. When off, no new events or identification are
collected. The SDK is not initialized at an opted-out launch. Requests already
in flight may finish. Previously collected events can remain in a bounded
100-event queue and may be delivered when analytics is re-enabled. Reset and
opt-out do not erase historical vendor data. This policy does not promise a
time-based queue expiration or deletion of previously collected activity.

The SDK's supported URLSession configuration routes requests through an
app-owned gate. Only POST requests to the configured batch endpoint can leave
the app while the gate is enabled. Redirects, configuration requests, flags,
replay, logs and push endpoints are refused. The internal routing header is
removed before forwarding. The adapter also disables unused SDK collection
options and sanitizes SDK-added properties before queuing an event.

Only the identity event's generated anonymous join ID is retained in addition
to the approved account identity. No person properties are supplied. Events
include fixed platform, environment and app version, the SDK/session fields
listed in `AnalyticsPayload`, and an explicit request to skip GeoIP enrichment.
Server-side ingestion settings and enrichment still require release evidence.

## Configuration

Tracked Debug and Release configurations leave analytics disabled. Missing or
invalid configuration yields a no-op adapter without affecting PocketBase,
startup or library flows. No production project token is included in source.

For isolated manual verification, use the gitignored Debug override:

```xcconfig
POSTHOG_PROJECT_TOKEN = <nonproduction public project token>
POSTHOG_HOST = https:/$()/us.i.posthog.com
ANALYTICS_ENVIRONMENT = preview
```

Debug builds reject `production`. UI tests, fixture launches and hosted unit
tests do not initialize analytics. Tests exercise the real SDK against an
intercepted HTTPS endpoint, not PostHog production. Release configuration can
use the same production project as web, after public disclosures and the
remaining release requirements are verified. Use the same opaque account ID
on both clients and add explicit `platform=web` where needed in the web app.

## Follow-up coverage

INT-1158 adds the rest of the meaningful reachable actions: authentication,
navigation, search/filter/sort, record changes, notes/photos, Account choices,
sync and conflict decisions. Add each typed name, trigger and property schema
before wiring it. Reuse web names only for matching meanings. Captures must
distinguish a durable local save from accepted synchronization, and retries
must not count as additional user actions.

First-use and activation milestones need a separately documented deduplication
policy. Device-local state cannot prove a first-ever action across web, iOS,
reinstalls and multiple devices. Do not add a parallel backend analytics store
or claim cross-device deduplication from local flags.

INT-1157 also owns the public web disclosure update. INT-1159 verifies the
backend-owned PostHog erasure handoff, retries, retention and unjoined events.
It must also verify dormant-device queues arriving after vendor deletion:
a successful deletion request alone does not prevent later re-ingestion.
INT-1160 verifies the assembled binary, manifests, App Store privacy answers
and live vendor processing before production enablement or submission.

## Verification and failure paths

- Missing configuration or vendor failure leaves product flows available.
- Opt-out prevents capture, identify and new batch requests. Reloading the
  account refreshes the shared preference. Opting back in uses the active
  account identity.
- Offline queued events retain their original identity through account changes.
  The queue has a count bound; delivery does not block product actions.
- Automatic requests and redirects cannot bypass the endpoint gate. Test the
  network boundary as well as SDK configuration.
- Actual serialized batches contain only registered events and allowed keys.
  SDK-added fields, person properties and free text are checked at this boundary.
- Run the local pre-PR gate on isolated iPhone and iPad iOS 26 simulators.
  Review the Account toggle, server persistence and Dynamic Type on both families.
- Use live nonproduction ingestion to confirm server enrichment and dashboard
  behavior separately from the isolated wire tests. Simulator tests do not
  establish vendor retention, deletion, physical-device or App Store evidence.
