# Native build sequence

**Date:** 2026-09-08 (revised same day: CRUD-first; Discord required; Randomizer deferred)  
**Companion:** [web-dev-feature-parity.md](./web-dev-feature-parity.md)

**Product bar:** the iOS app is a PocketBase client for adding and editing library data (projects, books, pages, notes, photos, lists, preferences). It is not a 1:1 clone of every web control.

**In near-term scope:** email auth, **Sign in with Discord**, create/edit/delete core records, progress notes, photos, Manage Lists, account preferences.

**Deferred:** Randomizer (leave the existing number picker as-is; do not expand it). Stats, timer, catalog, Google OAuth.

**App Store constraint (ADR-0007):** if the shipped binary offers Discord (or Google), Sign in with Apple is mandatory. Plan Apple for H1 even though it is not needed for TestFlight Discord.

## How to use this plan

- Work **one slice at a time**. Each slice should leave the app shippable: no disabled “Soon” that the slice was supposed to retire, no timer placeholders, no half-wired Create rows.
- Run **Track B (backend)** in parallel with **Track A (iOS)**. Do not stall daily-craft work on universal links or catalog billing.
- This plan targets **`origin/dev` `3651feba`** (PocketBase **0.40.1**) as the git contract. `ios/BackendContract.json` records that revision. The live server is **`https://data.organizedglitter.app`**, the same PocketBase the website has used for a long time. iOS already points there; there is no separate native backend.
- Backend *code* changes still land in `Interactive-Buffoonery/organized-glitter` first. Do not copy hooks, migrations, or schema into this repo.
- Keep `PocketBaseClient` as the only transport. Add methods there (multipart, confirm-token, custom routes). Do not add a repository protocol.
- Records stay in memory. Writes require connectivity. Last-write-wins; refresh after unknown completion (already the editor pattern).

## Definition of done, by horizon

| Horizon | User can | Must wait on Track B |
| --- | --- | --- |
| **H0 Everyday TestFlight** | Sign in with email **or Discord**, browse Library, create/edit core records, log notes and photos, manage lists and preferences | Native Discord redirect URL registered on the existing PocketBase Discord provider |
| **H1 App Store** | H0 plus Sign in with Apple, in-app account deletion, file-token-ready image loads, identity continuity, legal links (already present) | Apple provider + redirect, deletion endpoint, file-access contract, production pin verification |
| **H2 Auth continuity** | H1 plus in-app verify/reset/email-change confirmation | Associated Domains + token contract |
| **H3 Post-v1 product** | Timer, catalog/Supporter, URL kit import | New collections/billing; timer ADR |
| **H4 Web-only extras** | CSV, DAC, bulk photos, archive, marketing, PWA | Never required on iOS unless product changes |

PWA install, marketing pages, and desktop table view are **not** native work. Import/export stays on web for H0–H2.

---

## Track B — backend unblocks (start immediately, finish when ready)

These are not iOS feature PRs. They gate later slices. Owner: backend repo.

| ID | Work | Unblocks | Notes |
| --- | --- | --- | --- |
| B1 | Record `origin/dev` in `BackendContract.json` (done for `3651feba` / schema `e9d2569d…` / PocketBase 0.40.1). Re-pin when `dev` moves. | Contract file matches the backend this plan uses | Not a feature gate. Notes, photos, swatches, stats, Discord provider already exist on this revision. |
| B2 | File-access contract: protect **legacy** fields + short-lived tokens | App Store image privacy (H1) | Swatch photos are already protected. iOS already builds URLs in `PocketBaseClient.fileURL`. |
| B3 | Associated Domains file, HTTPS token routes, token format, web + old-app fallback | Verify email, confirm reset, confirm email change | Architecture already forbids guessing this. |
| B4 | Server-owned account deletion endpoint (no client-written audit) | In-app delete (H1) | Do not port the web `account_deletions` client flow. |
| B5a | Register native Discord OAuth redirect URL(s) for `ASWebAuthenticationSession` (custom scheme or HTTPS) on the **existing** Discord provider | Era 0 Discord button | Provider is already live. Same PocketBase user as web; never merge accounts by email on the client. |
| B5b | Apple OAuth provider + native redirect, and a Sign in with Apple button on web if the store binary will offer Discord | H1 | Guideline 4.8: third-party login on iOS requires Apple. Web today has Discord/Google UI; Apple is typed but unshipped. |
| B5c | Google OAuth native path | Optional later | Not required for H0. |
| B6 | `work_sessions` collection + ADR + Live Activity proof | Timer (H3) | Prove background presentation before any timer UI. |
| B7 | Catalog, Supporter, tips contracts | Catalog/billing (H3) | ADR-0021. Native billing is StoreKit, not PayPal. |
| B8 | URL kit-import API | Paste-URL create (H3) | Plan exists on web; not shipped. |

**Failure modes (Track B)**

| Failure | Trigger | Response |
| --- | --- | --- |
| Pin too old for a slice | Git `dev` has a new hook that is not on `data.organizedglitter.app` yet | Deploy that backend revision to the existing host; do not invent a client-side collection write |
| Deletion copied from web | Temptation to ship App Store faster | Refuse; keep mailto until B4 |
| Timer UI before B6 | “Just a stopwatch” | Out of scope; no Coming Soon control |
| File tokens forgotten | Ship H1 with public file URLs | H1 checklist fails; land B2 before submission |

---

## Track A — iOS eras

Each era lists **slices** (PR-sized), **depends on**, **exit criteria**, and **tests**. Slice IDs are the build order inside the era. Eras 0–5 are H0. Era 7 is H1/H2. Eras 8–9 are H3. Randomizer is not scheduled.

### Era 0 — Foundation and cheap wins

Unblock later eras and retire the obvious stubs. No new product surface except wiring what already exists.

| Slice | Work | Depends | Exit criteria |
| --- | --- | --- | --- |
| 0.1 | Decode remaining record fields used later (`is_mystery`, book notes/dates/ISBN, diamond dates/notes/URL/counts, page mediums if present, `revealed_at`) without new UI | — | Tests: decode fixtures; unknown keys ignored |
| 0.2 | Multipart `create`/`update` on `PocketBaseClient` (JSON + files); keep JSON path | — | Unit tests for body construction; no PII in logs |
| 0.3 | `fileURL` already centralized; add optional token parameter (no-op until B2) | 0.2 | Existing thumbs still work |
| 0.4 | Create tab: New coloring book opens `ColoringBookEditor` (already on Library) | — | No “Soon” on that row; vertical still gates it |
| 0.5 | Overview craft picker respects enabled verticals | — | Disabled craft omitted; Wishlist menu already gated |
| 0.6 | Authenticated change password (`oldPassword` / `password` / `passwordConfirm`) then sign out | — | Account row is change password, not “reset via email” for signed-in users |
| 0.7 | Sign in with Discord: `listAuthMethods`, `ASWebAuthenticationSession` (or equivalent), PocketBase OAuth2 code exchange, Keychain session same as email | B5a | Discord-only users reach the same `users` record as on web. Cancel, network, and account-conflict map to ADR-0007 categories. No email/password merge on the client. |

**Do not** add Google, Apple (until H1), deletion, Randomizer product work, or timer chrome here. Discord is required in Era 0 so existing Discord accounts can add library data.

### Era 1 — Progress notes (daily loop)

Highest-frequency missing craft action. Models already exist and are unused.

| Slice | Work | Depends | Exit criteria |
| --- | --- | --- | --- |
| 1.1 | Diamond notes: list on project detail; add (date + text); edit text; delete with confirm | 0.1 | Refresh-after-save; unknown-completion same as editors |
| 1.2 | Coloring-page notes: same on page detail | 1.1 | Notes attach to **page**, never book |
| 1.3 | Create → Add progress note: pick diamond project **or** coloring page, then composer | 1.1, 1.2, 0.4 pattern | Target required before write; verticals filter targets |
| 1.4 | Notes page: cross-craft timeline, month groups, load more; craft/year/source filters | 1.1–1.3 | Reachable from Overview and Account, **not** a sixth tab |
| 1.5 | Optional note image add/remove | 0.2, 1.1 | Display via `fileURL`; skip crop v1 if needed |

**Failure:** writing a coloring note onto a book. Response: types and UI never offer a book target.

### Era 2 — Photos

Unprotected URLs are acceptable for TestFlight (H0). H1 needs B2.

| Slice | Work | Depends | Exit criteria |
| --- | --- | --- | --- |
| 2.1 | Diamond cover: PhotosPicker, replace, remove; show on detail/library | 0.2 | MIME/size errors surfaced; HEIC via platform APIs |
| 2.2 | Book cover: retire “Cover upload is coming soon.” | 2.1 | Same pattern |
| 2.3 | Page photos: add, show all, delete, set-main; reorder if cheap | 2.1 | First photo remains library artwork |
| 2.4 | Shared image-normalize helper (type, size, downscale) | 2.1 | One place for all uploads |
| 2.5 | Tokenized `fileURL` once B2 is pinned | B2, 0.3 | No scattered URL string concat |

Native crop (web’s 4:3 dialog) is **polish after 2.3**, not a gate. Use PhotosPicker + optional `allowEditing` first.

### Era 3 — Complete craft records and Library

Reuse `TaxonomyPicker` (already used for publishers/illustrators).

| Slice | Work | Depends | Exit criteria |
| --- | --- | --- | --- |
| 3.1 | Diamond editor: company, artist (list + inline create), general notes, four dates, width/height, source URL; display color/diamond counts if we take them | 0.1 | Partial updates unchanged |
| 3.2 | Diamond tags on create/edit/detail | 3.1 | Join collection `project_tags`; do not invent a shared tag vocabulary with coloring |
| 3.3 | Library diamond filters: company, artist, drill, tags, year finished; mini/destashed/archived toggles | 3.1, 3.2 | Server-side filters; 2-char search gate |
| 3.4 | User-controlled sort for diamonds and books | 3.3 | Default stays last updated; pages stay page number unless we add a control |
| 3.5 | Book editor: mystery flag, notes, remaining bibliography (theme, ISBN, language, format, publication year, dates), coloring tags | 0.1 | Mystery chip on library cards; covers stay visible |
| 3.6 | Book detail contact sheet → page detail | 3.5 | Legacy >500 pages: batched fetch, not a hard cap that hides pages |
| 3.7 | Page editor: started/completed date fields (in addition to status-driven dates) | 3.6 | Reject completed-before-started |
| 3.8 | Overview: persist craft + sort; load more than 5; detail can edit | 0.5, 3.1 | Still not a KPI dashboard |
| 3.9 | Create → New coloring page: pick a book (pages are generated; this is “open/add via book total” or jump to last book). Prefer: pick book → book detail/pages. Do not client-create stray pages. | 3.6, 0.4 | No orphan `coloring_pages` create |

**Status counts** on Library can follow 3.3 (same query shape as web batch counts). Not a separate era.

### Era 4 — Manage Lists

Required for v1. Lower frequency than logging progress, so it follows the pickers that already need these collections.

| Slice | Work | Depends | Exit criteria |
| --- | --- | --- | --- |
| 4.1 | Account → Manage Lists hub, grouped by enabled craft | 3.1, 3.5 | Hidden group when vertical off |
| 4.2 | Companies, artists, diamond tags: list, create, edit, delete with confirm | 4.1 | Usage counts optional for v1; delete confirm required |
| 4.3 | Publishers, illustrators as full lists (not only inline create) | 4.1 | Matches book editor records |
| 4.4 | Coloring tags + coloring mediums CRUD | 4.1 | Mediums exist before Era 5 attach UI |

### Era 5 — Coloring page progress capture

| Slice | Work | Depends | Exit criteria |
| --- | --- | --- | --- |
| 5.1 | Attach/detach mediums on page; ownership errors surfaced | 4.4, 2.3 | Cannot attach another user’s medium |
| 5.2 | Mystery UX: reveal / edit subject / mark unrevealed; contact-sheet watermark for unrevealed | 3.5, 3.6 | Book `is_mystery` is metadata; reveal is per page |
| 5.3 | Color Codes & Swatches via `POST /api/coloring/pages/{pageId}/color-reference`, not collection CRUD; file tokens for those photos | 2.3, 0.3 | Empty references removed server-side; do not PATCH the collection |
| 5.4 | Page prev/next within book | 3.6 | Mismatched book/page id → not found |

### Era 6 — Randomizer (not scheduled)

Leave the current numbered-section picker in the tab. Do not build modes, wheel, spin history, Next Up, or notes-from-result unless product asks again. Users who want the full Randomizer keep using the website.

### Era 7 — Account remaining, App Store, auth continuity

| Slice | Work | Depends | Horizon |
| --- | --- | --- | --- |
| 7.1 | Avatar upload / revert to initials | 0.2, 2.4 | H0 |
| 7.2 | In-app deletion: confirm + reauth, call B4 only | B4 | H1 |
| 7.3 | Associated Domains + confirm verification / reset / email-change screens | B3 | H2 |
| 7.4 | Change-email request (confirm is 7.3) | 7.3 for completion | H2 |
| 7.5 | Sign in with Apple (required once Discord is in the App Store binary) | B5b, 0.7 | H1 |
| 7.6 | Google OAuth | B5c | Optional; not H0 |
| 7.7 | Coloring walkthrough (optional; once per account) | — | After H0 if desired |

**H1 submission checklist** (from architecture, not optional): deployed backend revision, PocketBase version, identity continuity, collection auth, backups, B4 deletion, B2 file tokens, Privacy/Terms links (done), **Sign in with Apple if Discord remains in the binary**.

### Era 8 — Stats

Not a bottom-nav slot. Add under Account or Overview accessory after H0 if the stats routes on the pinned backend are stable.

| Slice | Work | Depends |
| --- | --- | --- |
| 8.1 | Read-only Stats: craft scope, year/all-time, diamond + coloring regions | existing `/api/stats/*` on `origin/dev` |
| 8.2 | Do not compute collection splits on device if the server already does | 8.1 |

### Era 9 — Post-v1 product (H3)

| Slice | Work | Depends |
| --- | --- | --- |
| 9.1 | Timer ADR + Live Activity / Dynamic Island proof | B6 |
| 9.2 | Work sessions: one active timer, recover across launch, attach to project or page | 9.1, 1.x for optional companion note |
| 9.3 | Create → Add timed session **only after 9.2 is real** | 9.2 |
| 9.4 | Catalog search + barcode (Vision/data scanner) + five free adds / month | B7 |
| 9.5 | Supporter via StoreKit | B7, 9.4 |
| 9.6 | Tips (StoreKit one-shot; do not clone PayPal) | B7 |
| 9.7 | URL kit import on Add Project | B8 |

### Era 10 — Stay on the web (H4)

Do not schedule native CSV, DAC import, bulk photo ZIP, archive export/restore, marketing home, `/links`, or PWA install unless product explicitly reverses mobile v1. Users who need batch import keep using the website.

---

## Suggested calendar shape (not dates)

Work **Era 0 (including Discord) → 1 → 2** as the H0 spine (sign in, then add notes and photos). Start **B5a, B2, B4** on day one. Overlap **Era 3** with **Era 2** once covers work. **Era 4** after 3.1/3.5. **Era 5** after mediums exist (swatches do not wait on a pin bump). **Era 7** Apple + deletion as soon as B5b/B4 land. Do not wait on Randomizer.

```
Track B:  B5a ──────────────── B2 ── B4 ── B5b ── H1
                 └── B3 ──────────────────────── H2
                 └── B6 / B7 / B8 ────────────── H3

Track A:  0 (incl. Discord) ─ 1 ─ 2 ─┬─ 3 ─ 4 ─ 5 ── H0
                                      └─ 7.1
                                             7.2, 7.5 ── H1
                                             8, 9 ────── H3
```

## Architecture constraints to keep

- Swift 6, iOS 18+, availability for newer APIs.
- Feature state local; inject `PocketBaseClient` and user id.
- Partial updates; refresh after unknown write completion.
- Verticals gate **entry points**, not historical records (timer spec; also tags/notes).
- Separate diamond vs coloring tag vocabularies.
- No offline write queue. No realtime. No “Soon” timer.
- Never log tokens, emails, file URLs, or user content.

## Testing bar per slice

Match existing style: Swift Testing for models/filters/writes; UI tests for the slice’s happy path and empty/error; iPhone 17 + iPad destination. Seeded PocketBase tests stay opt-in. Screenshot tests only when the slice changes a validated surface (Overview, Library, account entry).

## What this plan refuses

- Cloning Dashboard table view as a v1 requirement.
- Client-side account deletion audit writes.
- Color-reference writes through ordinary collection APIs.
- Native import/export as a shortcut around web Data tab.
- Building catalog paywalls before B7.
- Six-tab navigation (Notes and Stats are pages, not slots).
- Expanding Randomizer before CRUD, notes, and photos are done.
- Merging Discord and email accounts on the client.
