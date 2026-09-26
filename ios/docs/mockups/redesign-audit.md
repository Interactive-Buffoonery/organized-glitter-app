# iOS UI audit

Snapshot of `main` at `6689a6a` (after #6, native refinement). Mockups are in `redesign-options.html`, next to this file. Web parity lives in `../audits/web-dev-feature-parity.md` and `../audits/native-build-sequence.md`.

## Direction

**Option B, "Shelf"**, is the chosen direction. It is artwork-first: a covers grid in Library and a hero cover on detail screens.

Records without an upload still need to look good, so they get a **generated cover**, the way Apple Books does it:

- a Berry Cream gradient seeded by the record id, so the same record always gets the same cover
- the title set in Caveat
- a small craft glyph

A first run with an empty library shows one "Add your first kit" prompt instead of an empty grid.

## Structure

1. **Every screen has two titles.** `OverviewView`, `QuickCreateView`, and the randomizer still set `.navigationTitle` and also render a Caveat `PageHeader`. Use system large titles, then delete `PageHeader` and `SectionHeader`.
2. **Search sits above the title.** On iOS 26, use `Tab(role: .search)`. On iOS 18, `.searchable` with system large titles already orders correctly.
3. **Five tabs, and two aren't destinations.** Create is an action: move it to a toolbar `+` `Menu`. Randomizer is optional for v1. Account can open from a toolbar avatar button.
4. **iPad has nested sidebars.** `LibraryView` puts a `NavigationSplitView` inside a `.sidebarAdaptable` `TabView`. Use `TabSection` so the crafts become sidebar rows.
5. **`.toolbarBackground(.hidden)`** has moved to `LibraryItemDetail`, where it still fights the iOS 26 scroll edge effect. Keep it only if the Shelf hero cover runs under the nav bar.

## Visual

6. **Two design languages.** Only Create still uses `StickerCard`, `IconBadge`, and hard offset shadows. Once Create becomes a menu, delete them and their tokens.
7. **Create is mostly stubs.** It still has "Soon" rows.
8. **Records with no artwork.** Grid frames are now fixed (`LibraryGalleryCard`). Records without an image need the generated cover described under Direction.
9. **Filters look like text fields.** Use a toolbar filter `Menu` or status chips.
10. **Run-on stats footnote** in `OverviewView` ("Active diamond projects: X · …"). Make it rows or drop it.
11. **Filler copy.** "Start something sparkly." is still in Create.
12. **The dark-mode segmented control is untinted.**

## Features

13. **Detail is better but incomplete.** #6 added detail screens with progress notes, photos, add-note, and actions. Company, artist, size, diamond count, tags, dates, and source link are still missing.
14. **The diamond editor covers 4 fields** (title, kit, drill shape, status). About 12 web fields are missing.
15. **Features missing compared with the web app:** stats, taxonomy management, import/export, change email/password, and **in-app account deletion**. Account deletion still goes through `mailto:`, which fails App Store guideline 5.1.1(v). See the parity audit for the full list.
16. **The time zone picker** still lists every `knownTimeZoneIdentifiers` entry in a single `Picker`. Use a searchable list.

## Backend-dependent

17. **Thumbs don't match the allowlist.** iOS now asks for `ArtworkThumb.gallery` (`320x420`) and `.compact` (`160x160`), but on backend `dev` only `projects.image` has thumbs (`300x200`, `600x400`), and neither size matches. PocketBase serves originals. Add matching thumb sizes in an `organized-glitter` migration first.
18. **Protected files.** Backend #289 (merged to `dev` 2026-09-26) protects every file field. iOS file tokens are in app PR #7. Both must reach production before public release.
19. **`BackendContract.json` still pins `6aff8ce`.** Re-pin to `3651feba` or later in its own PR once that revision is verified against production.

## Code hygiene

20. **`.listRowBackground(theme.card)`** appears 21 times. Apply it once, or hide the scroll content background.
21. **`EmptyFeatureView`** is a one-line wrapper around `ContentUnavailableView`. Inline it.
22. **Statuses are stringly typed.** Use one `enum` per collection, with `label` and `systemImage`.

Resolved by #6: the `LibraryView` split (model, gallery, and detail are now separate files), the ragged gallery, thumb plumbing through `PocketBaseClient.fileURL(thumb:)`, detail screens, and the log-progress path.

## Suggested order

1. Land #7 (file tokens) so images keep loading once #289 deploys (18).
2. Shelf: generated covers, the covers grid, and the hero detail (8). Drop duplicate titles and filler copy along the way (1, 10, 11).
3. Collapse the tabs, turn Create into a menu, and delete the sticker system (3, 6, 7).
4. Add in-app account deletion (15), which blocks release.
5. Fill out detail fields and the editor (13, 14).
6. Thumb sizes, backend first (17).
7. iPad `TabSection` (4).
