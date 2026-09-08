# iOS feature parity audit vs web `dev`

**Date:** 2026-09-08  
**Question:** For every user-facing capability on the web `dev` branch, is it included, incomplete, or missing in this iOS app?

## Snapshots compared

| Side | Repository | Ref | SHA | Date |
| --- | --- | --- | --- | --- |
| Web product + backend | `Interactive-Buffoonery/organized-glitter` | `origin/dev` | `3651feba64885af3b59f8232de2ed0d2653ce2ba` | 2026-09-08 |
| iOS app | this repository | `main` at audit start | `ab385b737fa24f4bc8ce74450ff85155489137ca` | 2026-09-07 |
| iOS backend pin | `ios/BackendContract.json` | backend commit | `6aff8ce42e7360513131a10ceb1c9478afb828f8` | 2026-07-22 |

The iOS contract pin is **205 commits behind** `origin/dev`. Several shipped web features (color references, randomizer redesign, archive schema v2) landed after that pin. Native work that needs those contracts should wait until the matching backend revision is verified and the pin is updated.

Evidence is from source inspection, not a live dual-client walkthrough. Web inventory also used `docs/feature-inventory.csv` (generated 2026-06-21) and was re-checked against `origin/dev` routes and pages. Color Codes & Swatches shipped on web after that CSV (`c54aa95`, 2026-09-07) and is included here.

Product intent for native launch is `docs/mobile/mobile-v1-scope.md` on web `dev`. This audit reports **web vs iOS**, then notes whether mobile v1 treats the gap as in-scope, excluded, post-v1, or silent.

## How to read status

| Status | Meaning |
| --- | --- |
| **Included** | iOS has a usable path for the job. It may look native rather than cloning every web control. |
| **Incomplete** | iOS shows the surface or a subset of fields, but the web job is not finished. |
| **Missing** | Web has a user-facing path; iOS has none (models or comments do not count). |
| **Stub** | Visible iOS chrome that does not act (`Soon`, coming-soon copy). Counted with Incomplete. |
| **Blocked** | Native cannot finish until backend/contract work ships. |
| **Out of v1** | Web has it; mobile v1 explicitly excludes it. Still listed so the gap is visible. |
| **Planned** | Not a shipped web product UI either (catalog, URL kit import, timer, Supporter). |

## Headline

The iOS app is a working **online-only library client** for email auth, Overview, three-section Library browse, diamond/book/page core CRUD, craft preferences, and a local numbered-section picker. It is **not** workflow-parity with web `dev`.

The largest in-scope holes are: OAuth continuity, in-app token confirmation, photos, progress notes, Manage Lists, a real Randomizer, diamond metadata (company/artist/tags/dates/notes/cover), coloring page progress capture (photos, mediums, mystery book flag, swatches), Notes, Stats, avatar, change-email, and account deletion.

---

## 1. Authentication and session

| Feature | Web `dev` | iOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Welcome / method choice | Login and Register pages | `WelcomeView` → `AccountMethodView` | **Included** | Email only. |
| Email/password sign-in | `Login` + `AuthForm` | `SignInView` → `PocketBaseClient.signIn` | **Included** | |
| Registration (email, username, password) | `Register` | `RegistrationView` | **Included** | Also requests verification. |
| Request verification email | `EmailConfirmation` | `VerificationRequestView` | **Included** | |
| Confirm verification via token/link | `/auth/verify-email/:token` | none | **Missing / Blocked** | Copy tells users to open the email on the web. Needs Associated Domains + token contract. |
| Request password reset | `ForgotPassword` | `PasswordResetView` | **Included** | |
| Confirm password reset via token | `/auth/confirm-password-reset/:token` | none | **Missing / Blocked** | Same universal-link block. Account still offers this request screen as “Reset password”. |
| OAuth Google | `SocialLogin` | none | **Missing** | Intentionally omitted until a native continuity path is verified. |
| OAuth Discord | `SocialLogin` | none | **Missing** | Same. |
| Sign in with Apple | typed in web OAuth provider, **no web UI** | none | **Planned** on both | Web has no Apple button either. |
| Session restore from secure storage | PocketBase auth store | Keychain + `auth-refresh` | **Included** | |
| Offline / failed restore with retry | `OfflinePage` | `ConnectionUnavailableView` | **Included** | Online-only; no write queue. Matches architecture. |
| Protected signed-in shell | `ProtectedRoute` | `RootView` phases | **Included** | |
| Unverified-user handling | Server auth then client clear | sign-in error path | **Included** | Not a full in-app verify-and-retry loop. |

iOS evidence: `Authentication/*`, `App/RootView.swift`, `App/AppModel.swift`, `ios/docs/architecture.md`, `ios/docs/account-entry-validation.md`.

---

## 2. App shell and navigation

| Feature | Web `dev` | iOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Five-slot mobile nav | Overview, Dashboard, Create, Randomizer, account menu | Overview, Library, Create, Randomizer, Account | **Included** | Native uses the intended Library + Account labels. Web PWA still says Dashboard. |
| iPad adaptive chrome | desktop header | `.sidebarAdaptable` tabs | **Included** | Native-only. |
| Vertical gating of nav/create | enabled crafts hide destinations | Library/Create gated; Overview craft picker is **not** | **Incomplete** | Overview still offers All / Diamond art / Coloring regardless of toggles. Wishlist menu is gated. |
| Centered Create slot | quick-create menu | Create tab | **Incomplete** | See §6. |
| Notes as a real page, not a tab | `/notes` | none | **Missing** | In-scope for v1, not a primary tab. |
| Stats in chrome | header `/stats`; not in bottom nav | none | **Missing** | Silent in mobile v1 scope. |

iOS evidence: `App/AppShellView.swift`.

---

## 3. Overview

| Feature | Web `dev` | iOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Signed-in landing | `/overview` | Overview tab | **Included** | |
| In-progress feed (diamond `progress` + coloring page `in_progress`) | `OverviewActivityList` | `OverviewModel` lists (5 each, merged by `updated`) | **Incomplete** | Caps at 5 per craft; no “load more”; detail is read-only (`LibraryItemDetail` without Edit/Delete). |
| Craft filter | All / diamond / coloring, persisted | All / Diamond art / Coloring | **Incomplete** | Not persisted; not gated by verticals. |
| Sort (recent / oldest / name) | `OverviewSortControl`, localStorage | none | **Missing** | Hardcoded `-updated`. |
| Snapshot counts | active diamonds, in-progress pages, completed this month | same three counts in a footnote | **Included** | Month bounds use GMT `startOfMonth`. |
| Wishlist jump into Library | not the same control | menu → Library with `wishlist` | **Included** | Native-specific handoff; books or diamonds only. |
| Progress notes on Overview | latest-note activity on web rows | none | **Missing** | |
| Active timer on Overview | n/a (timer unshipped) | none | **Planned / post-v1** | Do not add placeholders. |

iOS evidence: `Overview/OverviewView.swift`, `ios/docs/overview-validation.md`.

---

## 4. Library browse

Web still uses `/dashboard` with a craft toggle of **Diamond** vs **Coloring books**. iOS Library has three peer sections: Diamond projects, Coloring books, Coloring pages. That three-section IA is what mobile v1 asked for; web does not have a peer Pages library.

### Shared browse

| Feature | Web `dev` | iOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Paginated listing | page size 25/50/100 | infinite load on last cell | **Included** | Native pagination, not cloned page-size UI. |
| Pull to refresh | refetch | yes | **Included** | |
| Search (server, 2+ chars) | diamond + coloring search | `.searchable` → PocketBase | **Included** | |
| Status filter | status segments + counts | status menu, no live counts | **Incomplete** | No per-status count bar. |
| User-controlled sort | many fields + nulls-last | hardcoded `-updated` (pages `+page_number`) | **Missing** | |
| Grid / list / table views | three view types | gallery grid only | **Incomplete** | Native gallery is the intended Library look; table is a desktop affordance. |
| Empty / error / retry | yes | yes | **Included** | |
| iPad craft sidebar | n/a | `NavigationSplitView` | **Included** | Phone uses a segmented/menu picker. |

### Diamond filters (web Dashboard)

| Feature | iOS status | Notes |
| --- | --- | --- |
| Status | **Included** | All nine statuses. |
| Company | **Missing** | |
| Artist | **Missing** | |
| Drill shape | **Missing** | |
| Year finished | **Missing** | |
| Tags (multi) | **Missing** | No tag models in the client. |
| Search all fields (notes/URL) | **Missing** | Title-oriented search only. |
| Include mini / destashed / archived toggles | **Missing** | Archived/destashed appear only if that status is chosen. |
| Quick view presets | **Missing** | Waiting to arrive, Ready to start, In progress, Finished this year. |

### Coloring-book filters (web Coloring pane)

| Feature | iOS status | Notes |
| --- | --- | --- |
| Status | **Included** | |
| Publisher / illustrator | **Missing** | |
| Tags | **Missing** | |
| Mystery-only | **Missing** | Book record does not even decode `is_mystery`. |
| Include archived / destashed | **Missing** | Same as diamonds: only via explicit status. |

iOS evidence: `Diamonds/LibraryView.swift`, `ios/docs/library-validation.md`.

---

## 5. Record detail, create, edit, delete

### Diamond projects

Web: full form (title, status, company, artist, tags, drill, kit, dimensions, diamond count, color count, four dates, source URL, general notes, croppable cover), detail hero, timeline date editors, inline notes, tags, progress notes, archive, delete.

| Feature | iOS | Status |
| --- | --- | --- |
| Create from Library | `DiamondProjectEditor` sheet | **Incomplete** — title, status, kit full/mini, drill shape only |
| Create from Create tab | same editor | **Incomplete** — same fields |
| Edit | same editor | **Incomplete** — same fields |
| Detail | artwork, title, company/artist subtitle if expanded, status, kit, drill, size if width/height present | **Incomplete** — no notes, dates, tags, source URL, color count, diamond count |
| Cover image display | `AsyncImage` via `fileURL` | **Included** (read-only) |
| Cover upload / crop / remove | none | **Missing** |
| Company / artist assign | decoded on list/detail; not editable | **Missing** |
| Tags | none | **Missing** |
| General notes | on `DiamondProjectRecord`; not shown or edited | **Missing** |
| Purchase / received / started / completed dates | started/completed decoded; not shown or edited | **Missing** |
| Status change | editor picker (not inline on detail) | **Incomplete** |
| Archive | status `archived` in picker | **Included** as a status, not a dedicated archive action |
| Delete | Library detail toolbar | **Included** |
| Dimensions | display if present; not editable | **Incomplete** |

### Coloring books

Web: title, pages, status, series, theme, ISBN, source URL, notes, edition, dates, publication year, format, language, mystery flag, publisher, illustrator, cover crop, tags, page contact sheet, delete.

| Feature | iOS | Status |
| --- | --- | --- |
| Create from Library | `ColoringBookEditor` | **Incomplete** — title, series, status, total pages, publisher, illustrator |
| Create from Create tab | card labeled **Soon** | **Stub** |
| Edit | same editor | **Incomplete** — same fields |
| Publisher / illustrator pick + inline create | `TaxonomyPicker` on `book_publishers` / `book_illustrators` | **Included** |
| Cover display | existing cover only | **Incomplete** |
| Cover upload | “Cover upload is coming soon.” | **Stub** |
| Mystery flag (`is_mystery`) | not in DTO or UI | **Missing** |
| Theme, ISBN, source URL, notes, edition, language, format, publication year, lifecycle dates | none | **Missing** |
| Book tags | none | **Missing** |
| Page contact sheet on book detail | none; pages are a Library section | **Incomplete** | Web job (open book → see all pages) has no native equivalent |
| Delete book | Library toolbar | **Included** |
| Page generation from `total_pages` | relies on PocketBase hook after save | **Included** | Footnote explains untouched excess pages are removed |

### Coloring pages

Web page detail is the main coloring progress surface: status, dates, photos, mediums, mystery reveal/unreveal, progress notes, color references.

| Feature | iOS | Status |
| --- | --- | --- |
| Browse pages as a Library section | yes | **Included** | Ahead of web IA |
| Create a page from UI | Create tab **Soon**; Library has no add | **Stub / Missing** | Pages are generated from book `total_pages` |
| Edit status | `ColoringPageEditor` | **Included** |
| Revealed subject | text field | **Incomplete** | No mystery-book gate, no dedicated unreveal, no `revealed_at` |
| Photo display (first photo) | read-only thumbnail | **Incomplete** |
| Photo upload / crop / reorder / delete / set-main | none (`PhotosPicker` unused) | **Missing** |
| Mediums attach/detach | none | **Missing** |
| Started/completed date editing | footnote: set from status | **Incomplete** | Matches hook behavior; web also allows manual dates |
| Page progress notes | models exist; no UI | **Missing** |
| Color Codes & Swatches | none | **Missing** | Shipped on web `dev` after the June inventory |
| Delete page | `LibraryModel.delete` returns early for `.page` | **Missing** |
| Prev/next page navigation | none | **Missing** |

iOS evidence: `Diamonds/DiamondProjectEditor.swift`, `Coloring/ColoringEditors.swift`, `Coloring/TaxonomyPicker.swift`, `Networking/PocketBaseRecords.swift`.

---

## 6. Quick Create

Mobile v1 wants grouped Create (diamond, book, page) and Log (progress note; timed session only after that feature ships).

| Entry | iOS | Status |
| --- | --- | --- |
| New diamond project | opens editor | **Incomplete** | Editor field set is thin (see §5) |
| New coloring book | **Soon** | **Stub** | Book create **does** exist from Library |
| New coloring page | **Soon** | **Stub** | |
| Add progress note | **Soon** | **Stub** | Models `DiamondProgressNoteRecord` / `ColoringProgressNoteRecord` are unused |
| Add timed session | absent | **Correctly absent** | Post-v1; do not add a disabled control |

iOS evidence: `App/QuickCreateView.swift`.

---

## 7. Progress notes and Notes page

| Feature | Web `dev` | iOS | Status |
| --- | --- | --- | --- |
| Diamond note create (date, caption, optional photo) | project detail + Notes + Create | none | **Missing** |
| Diamond note edit / delete / remove image | yes | none | **Missing** |
| Coloring-page note create / edit / delete | page detail + Notes | none | **Missing** |
| Cross-craft Notes timeline | `/notes`, month groups, load more | none | **Missing** |
| Filter Notes by craft / year / source | yes | none | **Missing** |
| Add note from feed with target picker | `AddNoteCTA` / `NoteTargetPicker` | Create stub only | **Missing** |

In-scope for mobile v1. Highest-frequency craft action after status changes.

---

## 8. Randomizer

Web `/randomizer` is a full craft-decision surface: modes, eligibility, target pool, numbered wheel, persist `randomizer_spins`, Next Up, history, book→page drill-in, diamond size+number section helper, progress notes from the result.

iOS Randomizer tab is **only** the local numbered-section picker.

| Feature | iOS | Status |
| --- | --- | --- |
| Number-mode section picker (comma-separated, pick/retry) | `NumberSectionPicker` | **Included** | Local only; complete for that isolated job |
| Size-mode section picker (3×3 / 4×4 / 5×5 / custom cm) | none | **Missing** |
| Craft modes (diamond / book / page) | none | **Missing** |
| Status eligibility filters | none | **Missing** |
| Target list, select all/none, search | none | **Missing** |
| Wheel UI + persist spin | none | **Missing** | Dice button is local random, not a wheel |
| Spin history | none | **Missing** |
| Next Up per mode | none | **Missing** | Lives in `user_dashboard_settings.randomizer_next_up` on web |
| Book result → random unfinished page | none | **Missing** |
| Progress note from result | none | **Missing** |
| Copy that picks are not saved | footnote on screen | **Incomplete** vs product job | Explicit: “Picks stay on this screen and are not saved to a project.” |

iOS evidence: `Randomizer/RandomizerView.swift`, `Randomizer/NumberSectionPicker.swift`, `ios/docs/number-section-picker-validation.md`.

---

## 9. Account, profile, preferences

| Feature | Web `dev` | iOS | Status |
| --- | --- | --- | --- |
| Username / profile name | inline edit + availability | `ProfileNameView` | **Included** |
| Email display | read-only + Change | read-only | **Incomplete** |
| Change email + confirm token | `/change-email`, `/auth/confirm-email-change/:token` | none | **Missing / Blocked** | Token confirm needs the same universal-link work |
| Change password (authenticated) | current + new, then sign out | “Reset password” = email request only | **Incomplete** |
| Avatar upload / revert to initials | `AvatarManager` | `UserRecord.avatar` unused | **Missing** |
| Theme: system / light / dark | account-level Berry Cream | same three flavors via `theme_preference` | **Included** |
| Timezone | preference picker | `TimeZone.knownTimeZoneIdentifiers` | **Included** |
| Craft vertical toggles (at least one on) | Profile > Preferences | Account > Crafts | **Included** |
| Logout | yes | Sign Out | **Included** |
| Delete account in-app | `DeleteAccount` writes audit then deletes user | mailto “Account deletion help” only | **Missing / Blocked** | Architecture forbids copying the web client-written audit flow. Needs a server-derived deletion endpoint. |
| Support / feedback mailto | Profile > Support | Help and legal links | **Included** |
| Privacy / Terms (live web pages) | in-app pages + public routes | `Link` to public URLs | **Included** |
| App information | PWA install, version-ish help | `AppInformationView` | **Included** |
| PayPal donate / `/support/success` | shipped | none | **Missing** | Not specified in mobile v1 |
| PWA install prompt | shipped | n/a | **Out of v1** | Native app does not need this |
| Coloring walkthrough modal | once per account | none | **Missing** | Silent in mobile v1 |

iOS evidence: `Account/AccountView.swift`, `Account/AccountPreferencesModel.swift`, `Account/AccountDestinations.swift`.

---

## 10. Manage Lists

Required under Account in mobile v1. Forms should also allow inline create when saving a craft record.

| List | Web | iOS | Status |
| --- | --- | --- | --- |
| Hub page grouped by craft | `/options` | none | **Missing** |
| Diamond companies CRUD | `/options/companies` | none | **Missing** | No company picker on diamond editor either |
| Diamond artists CRUD | `/options/artists` | none | **Missing** |
| Diamond tags CRUD (color, usage) | `/options/tags` | none | **Missing** |
| Coloring tags list/delete | same tags page | none | **Missing** |
| Publishers CRUD | `/options/publishers` | inline create in book editor only | **Incomplete** | No list/edit/delete hub |
| Illustrators CRUD | `/options/illustrators` | inline create in book editor only | **Incomplete** |
| Coloring mediums CRUD | `/options/coloring-mediums` | none | **Missing** |

---

## 11. Stats

| Feature | Web `dev` | iOS | Status |
| --- | --- | --- | --- |
| Stats page, craft/year scope | `/stats` | none | **Missing** |
| Diamond completions, library, timing, collection splits | shipped | none | **Missing** |
| Coloring completions, library, timing, collection splits | shipped | none | **Missing** |

Silent in mobile v1 (doc mentions stats *routes* for the client, not a Stats tab). Still a web-vs-iOS product gap.

---

## 12. Import / export (web Data tab)

Mobile v1 **excludes** CSV, bulk, and desktop-batch workflows.

| Feature | iOS | Status |
| --- | --- | --- |
| Organized Glitter CSV import | none | **Out of v1** |
| Diamond Art Club CSV import | none | **Out of v1** |
| Bulk photo ZIP/folder import | none | **Out of v1** |
| Full archive ZIP export | none | **Out of v1** |
| Archive restore | none | **Out of v1** |
| CSV-only library exports | none | **Out of v1** |

These remain available on web Settings → Data. Native should not grow a second import stack unless product intent changes.

---

## 13. Public / marketing (web-only)

Not native app features. iOS Account already links Privacy and Terms.

| Feature | iOS | Status |
| --- | --- | --- |
| Marketing home, About, Links, 404 | none | **Out of v1** | Correct |
| Privacy / Terms content | opened as web pages | **Included** as links |

---

## 14. Planned on web `dev` (not shipped in either client)

| Feature | Web | iOS | Notes |
| --- | --- | --- | --- |
| Diamond catalog search + barcode scan | ADR-0021 + plans only | none | First paid feature; five free catalog adds / month |
| Supporter subscription | planned | none | StoreKit would be the native path later |
| Developer tips | planned (PayPal exists as donate, separate) | none | |
| URL kit import | proposed plan 2026-09-07 | none | |
| Work sessions / timer | CONTEXT + mobile v1 post-v1 spec; no `work_sessions` | none | Do not show Coming Soon timer UI |
| Sign in with Apple | type only on web | none | |

---

## 15. Backend / platform gaps that block native completeness

From `ios/docs/architecture.md` and this comparison:

1. **Universal links** for verify-email, confirm-password-reset, and confirm-email-change (Associated Domains file, stable HTTPS routes, token format, fallback for older apps and web).
2. **Account deletion** as one authenticated server endpoint that writes an immutable audit record from server context, then deletes. Do not port the web client-written `account_deletions` flow.
3. **Protected file fields + short-lived file tokens** (`docs/FILE_ACCESS_CONTRACT.md` on web; still a native public-release blocker). All iOS image loads go through `PocketBaseClient.fileURL` so the token query can land in one place.
4. **Backend pin drift:** native is pinned to PocketBase **0.37.5** / commit `6aff8ce` (2026-07-22). Color references use a transactional route, not collection CRUD; do not add that UI against the current pin.
5. **OAuth native continuity** (Google, Discord, eventually Apple) is a product/auth-design problem, not just a missing button.

---

## 16. Collections vs iOS UI

What `origin/dev` schema/docs describe versus what this app actually reads or writes.

| Collection / API | iOS UI |
| --- | --- |
| `users` | sign-in, register, profile name, theme, timezone |
| `user_dashboard_settings` | vertical toggles only (not Next Up, not dashboard nav context) |
| `projects` | list/search/filter/create/edit/delete (subset of fields) |
| `coloring_books` | list/search/filter/create/edit/delete (subset of fields) |
| `coloring_pages` | list/search/filter/edit (no create/delete/photos) |
| `book_publishers`, `book_illustrators` | inline picker + create in book editor |
| `progress_notes` | DTO only |
| `coloring_page_progress_notes` | DTO only |
| `companies`, `artists`, `tags`, `project_tags` | unused |
| `coloring_tags` / book tag joins | unused |
| `coloring_mediums` | unused |
| `randomizer_spins` | unused |
| `coloring_page_color_references` + transactional route | unused |
| `account_deletions` | unused (must stay unused until the server-owned endpoint exists) |
| stats collections / `/api/stats/*` | unused |
| notes-feed / latest-notes helpers | unused |

`PocketBaseClient` public surface is auth + generic list/get/create/update/delete + `fileURL`. No OAuth, confirm-token, multipart upload, or custom routes.

---

## 17. Rollup

Counts below treat each table row in §§1–14 as one item. Stubs count as Incomplete. Out of v1 and Planned are listed separately so they are not mistaken for launch bugs.

### In-scope for mobile v1 (from `mobile-v1-scope.md`)

**Included enough to use daily**

- Email register / sign-in / request reset / request verification
- Session restore, offline retry, sign out
- Five-tab shell with Library and Account labels
- Overview in-progress list + month completion counts + Wishlist handoff
- Library browse across diamonds, books, and pages with search, status, pagination
- Diamond create/edit/delete for title, status, kit, drill
- Book create/edit/delete for title, series, status, pages, publisher, illustrator
- Page status + revealed-subject edit
- Theme, timezone, craft verticals, profile name
- Help/legal links
- Local numbered-section picker (not the Randomizer product)

**Incomplete (visible but not web-parity)**

- Overview (no sort/persist, 5-item cap, ungated craft picker, read-only detail)
- Library (no user sort, no facet filters, no status counts, gallery only)
- Diamond editor/detail (no company, artist, tags, notes, dates, cover write, counts, URL)
- Book editor (no mystery, bibliography extras, notes, tags, cover write, contact sheet)
- Page editor (no photos write, mediums, notes, swatches, delete, dates UI)
- Create tab (three of four entries are Soon; book create lives only on Library)
- Account email/password (display/request only)
- Publisher/illustrator (inline only, no Manage Lists)
- Randomizer tab (number picker only)

**Missing (in-scope, no iOS path)**

- OAuth Google/Discord
- In-app verification / reset / email-change confirmation
- Photos upload on every record type
- Progress notes everywhere, including Notes page and Create → Add progress note
- Manage Lists hub: companies, artists, tags, mediums (publishers/illustrators as hubs)
- Full Randomizer (modes, wheel, history, Next Up, notes from result, size mode)
- Avatar
- Authenticated change-password
- Change email
- Account deletion action (blocked)
- Book mystery flag and page mystery UX
- Coloring mediums on pages
- Color Codes & Swatches (shipped on web; not named in mobile v1, but it is page-detail progress capture)

### Explicitly out of v1 (web has them)

- CSV / DAC / bulk photos / archive export-restore
- Desktop table density, quick-view presets as a must-clone
- PWA install
- Marketing site

### Post-v1 / planned on both

- Work sessions / timer
- Diamond catalog, Supporter, tips, URL kit import
- Sign in with Apple

---

## 18. Suggested native sequence (not a commitment)

The full era-by-era plan, backend track, and exit criteria live in
[native-build-sequence.md](./native-build-sequence.md).

Near-term product intent (2026-09-08): **CRUD into PocketBase**, plus **Sign in with Discord**. Randomizer is deferred.

1. **Discord sign-in** (same PocketBase user as web) alongside existing email auth.
2. **Create/edit completeness** for diamonds, books, and pages (wire Create stubs, remaining fields).
3. **Progress notes** from detail and Create, then a Notes page.
4. **Photos** (project cover, book cover, page photos) via `fileURL`.
5. **Diamond metadata** and **Manage Lists** (company, artist, tags, dates, notes).
6. **Coloring page progress**: mediums, mystery, then color references after the backend pin includes that route.
7. **App Store:** Sign in with Apple (required if Discord is in the binary), file tokens, server-owned deletion.
8. **Not scheduled:** Randomizer product, Stats, Google OAuth, timer, catalog.

Do not add timer chrome, catalog paywalls, or import/export in this app until those decisions ship on the backend and in mobile scope.

---

## 19. Source index

**Web `origin/dev`**

- Routes: `src/components/routing/routeDefinitions.tsx`
- Scope: `docs/mobile/mobile-v1-scope.md`
- Inventory (stale in spots): `docs/feature-inventory.csv`
- Domain: `PRODUCT.md`, `CONTEXT.md`
- Schema: `docs/schema/collections.md`
- Color references: `docs/color-codes-and-swatches.md`

**iOS**

- Shell: `ios/OrganizedGlitter/App/`
- Auth: `ios/OrganizedGlitter/Authentication/`
- Overview: `ios/OrganizedGlitter/Overview/OverviewView.swift`
- Library / diamonds: `ios/OrganizedGlitter/Diamonds/`
- Coloring: `ios/OrganizedGlitter/Coloring/`
- Randomizer: `ios/OrganizedGlitter/Randomizer/`
- Account: `ios/OrganizedGlitter/Account/`
- Models: `ios/OrganizedGlitter/Networking/PocketBaseModels.swift`, `PocketBaseRecords.swift`, `PocketBaseClient.swift`
- Policy: `ios/docs/architecture.md`, `ios/BackendContract.json`
