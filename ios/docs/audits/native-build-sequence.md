# Native build sequence

**Date:** 2026-09-08  
**Companion:** [web-dev-feature-parity.md](./web-dev-feature-parity.md)  
**Product bar:** workflow parity for everyday phone use (`docs/mobile/mobile-v1-scope.md` on web `dev`), then App Store gates, then post-v1 product. This is not a 1:1 clone of every desktop control.

This plan sequences **all** gaps in the parity audit: mobile v1, App Store blockers, post-v1 product, and desktop-class extras that should stay on the web unless product intent changes.

## How to use this plan

- Work **one slice at a time**. Each slice should leave the app shippable: no disabled “Soon” that the slice was supposed to retire, no timer placeholders, no half-wired Create rows.
- Run **Track B (backend)** in parallel with **Track A (iOS)**. Do not stall daily-craft work on universal links or catalog billing.
- Backend changes land in `Interactive-Buffoonery/organized-glitter` first. Do not copy hooks, migrations, or schema into this repo. Do not edit `ios/BackendContract.json` until that revision is verified.
- Keep `PocketBaseClient` as the only transport. Add methods there (multipart, confirm-token, custom routes). Do not add a repository protocol.
- Records stay in memory. Writes require connectivity. Last-write-wins; refresh after unknown completion (already the editor pattern).

## Definition of done, by horizon

| Horizon | User can | Must wait on Track B |
| --- | --- | --- |
| **H0 Everyday TestFlight** | Sign in with email, browse Library, create/edit core records, log notes and photos, randomize what to work on, manage lists and preferences | Backend pin current enough for notes/photos/randomizer collections |
| **H1 App Store** | H0 plus in-app account deletion, file-token-ready image loads, identity continuity, legal links (already present) | Deletion endpoint, file-access contract, production pin verification |
| **H2 Auth continuity** | H1 plus OAuth, in-app verify/reset/email-change confirmation | Associated Domains + token contract; OAuth native path |
| **H3 Post-v1 product** | Timer, catalog/Supporter, URL kit import | New collections/billing; timer ADR |
| **H4 Web-only extras** | CSV, DAC, bulk photos, archive, marketing, PWA | Never required on iOS unless product changes |

PWA install, marketing pages, and desktop table view are **not** native work. Import/export stays on web for H0–H2.

---

## Track B — backend unblocks (start immediately, finish when ready)

These are not iOS feature PRs. They gate later slices. Owner: backend repo.

| ID | Work | Unblocks | Notes |
| --- | --- | --- | --- |
| B1 | Choose and verify a `dev` backend revision; bump PocketBase if required; update `ios/BackendContract.json` only after verification | Almost everything after Era 0 | Pin is 205 commits behind `origin/dev`. Color references and randomizer metadata already exist on `dev`. |
| B2 | File-access contract: protected fields + short-lived tokens | App Store image privacy (H1) | iOS already builds URLs in `PocketBaseClient.fileURL`. Implement token query there only. Unprotected display can ship in Era 2. |
| B3 | Associated Domains file, HTTPS token routes, token format, web + old-app fallback | Verify email, confirm reset, confirm email change | Architecture already forbids guessing this. |
| B4 | Server-owned account deletion endpoint (no client-written audit) | In-app delete (H1) | Do not port the web `account_deletions` client flow. |
| B5 | Native OAuth continuity (Google, Discord; Apple later) | OAuth buttons | Web has Google/Discord; Apple is typed but unshipped on web too. |
| B6 | `work_sessions` collection + ADR + Live Activity proof | Timer (H3) | Prove background presentation before any timer UI. |
| B7 | Catalog, Supporter, tips contracts | Catalog/billing (H3) | ADR-0021. Native billing is StoreKit, not PayPal. |
| B8 | URL kit-import API | Paste-URL create (H3) | Plan exists on web; not shipped. |

**Failure modes (Track B)**

| Failure | Trigger | Response |
| --- | --- | --- |
| Pin too old for a slice | Color-reference route 404, unknown fields | Stop the slice; finish B1; do not invent a client-side collection write |
| Deletion copied from web | Temptation to ship App Store faster | Refuse; keep mailto until B4 |
| Timer UI before B6 | “Just a stopwatch” | Out of scope; no Coming Soon control |
| File tokens forgotten | Ship H1 with public file URLs | H1 checklist fails; land B2 before submission |

---

## Track A — iOS eras

Each era lists **slices** (PR-sized), **depends on**, **exit criteria**, and **tests**. Slice IDs are the build order inside the era. Eras 1–6 are H0. Era 7 is H1/H2. Eras 8–9 are H3. Era 10 is H4.

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

**Do not** add OAuth buttons, deletion, or timer chrome here.

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
| 5.3 | Color Codes & Swatches via transactional route, not collection CRUD | B1, 2.5 preferred | Empty references removed server-side; photos protected |
| 5.4 | Page prev/next within book | 3.6 | Mismatched book/page id → not found |

### Era 6 — Randomizer as a product

Keep the existing number picker. Do not throw it away.

| Slice | Work | Depends | Exit criteria |
| --- | --- | --- | --- |
| 6.1 | Modes: diamond / coloring book / coloring page, coerced to verticals | B1 | URL or in-memory mode; empty pool copy |
| 6.2 | Eligibility by status + target list (search, select all/none) | 6.1 | At least one target to spin |
| 6.3 | Persist `randomizer_spins`; result panel; history | 6.2 | Unknown JSON keys in metadata preserved |
| 6.4 | Native “spin” (picker/wheel). Numbered segments are the product; a SwiftUI wheel is optional | 6.3 | VoiceOver announces winning number |
| 6.5 | Size-mode section helper + existing number-mode picker on diamond results | 6.4 | Discriminated `kind: size \| number` metadata |
| 6.6 | Next Up per mode in `user_dashboard_settings` | 6.3 | One slot per mode |
| 6.7 | Progress note from result (diamond and coloring page) | 1.3, 6.3 | Optional; spin does not require a note |
| 6.8 | Book result → random unfinished page | 6.3 | Error if none |

Remove the footnote “picks are not saved” when 6.3 ships.

### Era 7 — Account remaining, App Store, auth continuity

| Slice | Work | Depends | Horizon |
| --- | --- | --- | --- |
| 7.1 | Avatar upload / revert to initials | 0.2, 2.4 | H0 |
| 7.2 | In-app deletion: confirm + reauth, call B4 only | B4 | H1 |
| 7.3 | Associated Domains + confirm verification / reset / email-change screens | B3 | H2 |
| 7.4 | Change-email request (confirm is 7.3) | 7.3 for completion | H2 |
| 7.5 | OAuth Google/Discord | B5 | H2 |
| 7.6 | Sign in with Apple | B5 + web Apple UI | H2/H3 |
| 7.7 | Coloring walkthrough (optional; once per account) | — | After H0 if desired |

**H1 submission checklist** (from architecture, not optional): deployed backend revision, PocketBase version, identity continuity, collection auth, backups, B4 deletion, B2 file tokens, Privacy/Terms links (done).

### Era 8 — Stats

Not a bottom-nav slot. Add under Account or Overview accessory after H0 if the stats routes on the pinned backend are stable.

| Slice | Work | Depends |
| --- | --- | --- |
| 8.1 | Read-only Stats: craft scope, year/all-time, diamond + coloring regions | B1, existing `/api/stats/*` |
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

Work **Era 0 → 1 → 2** as a single H0 spine (notes then photos). Start **Track B1–B4** on day one. Overlap **Era 3** (metadata/filters) with **Era 2** once covers work. **Era 4** after 3.1/3.5 so lists are not empty chrome. **Era 5** after mediums exist. **Era 6** after notes exist so result-to-note is real. **Era 7** App Store items as soon as B2/B4 land, even if Randomizer is still mid-era. **Era 8–9** only after H1.

```
Track B:  B1 ──────────────── B2 ── B4 ── H1
                 └── B3 / B5 ──────────── H2
                 └── B6 / B7 / B8 ─────── H3

Track A:  0 ─ 1 ─ 2 ─┬─ 3 ─ 4 ─ 5 ─ 6 ── H0
                     └─ 7.1
                            7.2–7.6 ──── H1/H2
                            8, 9 ──────── H3
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
