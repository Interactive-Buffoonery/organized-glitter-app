# Library D migration validation

Date: 2026-09-07. Starting checkout: `chore/native-ui-cleanup` at `6052f01`,
with the Overview heading fix and subtitle removal already on the branch. No
commit, push, or PR was created.

Design reference: `Interactive-Buffoonery/organized-glitter` revision
`0135e6d3caa73ea01224bda27c8e0abbb954fd19`, including the studio README,
current client source, and its linked standalone refinement. ADR 0001 retains
control of native palette/background values. See [design.md](design.md).

This record is for the Library presentation and Wishlist handoff work. It does
not replace [Overview validation](overview-validation.md).

## Prior presentation checks (earlier Library D session)

These results are from the earlier Library presentation pass on this branch.
They were not re-run as a full matrix in the boundary-finish session below.

- Wishlist search handoff now reloads the unsearched listing. A focused test
  failed first: `LibraryModel.apply` cleared `searchText`, but the load task
  identity ignored that when section and status stayed the same. The fix adds
  `listingEpoch` to `listingIdentity`. `apply` still does not call `load()`, so
  the view task remains the single loader. Stale-response protection through
  `generation` is unchanged. Observable request filters and result titles were
  asserted, not only assigned fields.
- Debug simulator builds passed for iPhone 17 and OG Overview iPad (iOS/iPadOS
  26.5).
- Release simulator build passed on iPhone 17, including compilation with debug
  fixtures excluded.
- All Swift Testing tests then on the branch passed, including pagination,
  delayed craft switches, artwork URL construction, gallery captions, enabled-
  craft availability, and the repeating Wishlist handoff.
- iPhone UI tests passed for peer craft browsing and record identity, loading /
  empty / error / retry, accessibility craft menu and rotation, Overview
  filtering/detail, and Wishlist routing. The iPad sidebar test is skipped on
  iPhone.
- iPad UI tests passed for the craft sidebar (no iPhone segmented control),
  loading / empty / error / retry, and Wishlist routing to Books with the
  wishlist filter value and wishlist item.
- Largest accessibility Dynamic Type on iPhone switched craft selection to the
  native menu, stacked a single-column gallery, and still filtered to Books.
- Live screenshots were inspected in both appearances. Overview still shows the
  Caveat heading with no subtitle. Library shows the artwork-led gallery,
  missing-artwork fallback, quiet status, in-content add (no toolbar plus),
  iPad craft sidebar, and the ADR 0001 light gradient / dark navy with bottom
  purple glow. Backgrounds belong to the scroll viewport.
- `git diff --check` passed.

An earlier iPad three-column split hid the craft list and left a blank detail
pane. The Library iPad layout is now a two-column split: crafts in the sidebar,
gallery and details on the content stack. iPad tab targeting also had to use
the first Library button; iOS 26's adaptable tab bar is not an XCTest `TabBar`.

## Boundary finish checks (this session)

Focus: navigation and listing correctness after the stack/path migration. No
Library redesign. Approved palettes/backgrounds and Overview heading corrections
were left in place.

### Verified defects and fixes

1. **Stale detail after filter-mismatch save (HIGH).** After the path migration,
   `selectSaved` only assigned `path` when the saved id appeared in the reloaded
   page-1 listing. The previous split-view code assigned `selection` from
   `first(where:)`, which cleared detail when the record left the filter. The new
   code left the old `path` value in place, so detail could keep pre-edit
   content for a record no longer in the gallery.
   - Fix: `LibraryModel.selection(afterSaving:)` returns `nil` when the saved
     record no longer matches the current craft/status/search listing;
     `selectSaved` sets `path = []` on `nil`.
   - Regression:
     `savedSelectionClearsWhenStatusNoLongerMatchesTheFilter` asserts a nil
     selection and an empty wishlist listing after reload.

2. **Paginated edit lost after refresh (HIGH).** The same `selectSaved` path
   dropped detail for records reached through pagination when a reset reload
   only returned page 1.
   - Fix: when the saved record still matches the current listing filters but
     is absent from the loaded page, keep the saved snapshot in `path`.
   - Regression:
     `savedSelectionKeepsAnUpdatedRecordMissingFromTheFirstPage` failed under
     the page-1-only lookup and passes with the listing-match fallback. It
     asserts the updated title/id and that the final request is page 1.

3. **Coloring-only Library entry (MEDIUM).** `LibraryModel` still defaulted to
   diamonds. `onChange(of: verticals)` only ran after a preferences change, so
   opening Library after Account already had coloring-only enabled could load
   diamond projects while the craft picker only offered Books/Pages.
   - Fix: `LibraryModel.align(to:)` selects the first enabled craft; Library
     calls it from `init` and from the verticals `onChange`.
   - Regression:
     `alignUsesTheFirstEnabledCraftOnColoringOnlyAccounts`.

### Additional boundary coverage added

- `deleteRemovesTheRecordFromVisibleResults` — delete request plus refreshed
  titles without the deleted id.
- `delayedResponsesDoNotReplaceANewerStatusFilter` — generation guard under
  rapid status changes (craft race was already covered).
- Editor cancel / failed save / uncertain completion were confirmed against the
  unchanged editor save paths: cancel dismisses without `onSaved`; failed save
  keeps the sheet and does not call `onSaved`; offline/server uncertain refresh
  may call `onSaved` only when the refreshed record matches the draft, otherwise
  the sheet stays with `isCompletionUnknown`. Delete-while-viewing still clears
  `path` before `model.delete`.

### Commands and results from this session

All devices used iOS/iPadOS 26.5. Tests use isolated fictional fixtures; no live
backend or production data.

- `OrganizedGlitterTests`: **70** Swift Testing tests passed (was 65 before the
  new Library boundary cases).
- iPhone 17 UI: `LibraryUITests` (iPad sidebar skipped) plus Overview Wishlist
  and active-work detail tests — passed.
- OG Overview iPad UI: Library sidebar, loading/empty/error, Wishlist routing —
  passed (iPhone-only Library cases skipped).
- Debug builds: iPhone 17 and OG Overview iPad — succeeded.
- Release build: iPhone 17 — succeeded.
- `git diff --check` — passed.
- Red-proof: temporarily restoring the page-1-only `selection(afterSaving:)`
  made `savedSelectionKeepsAnUpdatedRecordMissingFromTheFirstPage` fail as
  expected; the fix was restored and re-verified green.

Reproduce from the repository root:

```sh
xcodebuild \
  -project ios/OrganizedGlitter.xcodeproj \
  -scheme OrganizedGlitter \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/og-library-boundary-build \
  -parallel-testing-enabled NO \
  test \
  -only-testing:OrganizedGlitterTests \
  -only-testing:OrganizedGlitterUITests/LibraryUITests \
  -only-testing:OrganizedGlitterUITests/OverviewUITests/testWishlistOpensFilteredLibrary \
  -only-testing:OrganizedGlitterUITests/OverviewUITests/testActiveWorkFilteringAndDetailNavigation
```

For iPad, use `platform=iOS Simulator,name=OG Overview iPad`.

## Prior Overview validation (not repeated here)

The Overview D migration on this branch was already validated at `1a4080c` and
followed by the heading fix at `6052f01`. That earlier pass covered Overview
UI states, iPad Overview, contrast over the dark glow, Reduce Motion, and
fixed-position background samples. This Library work re-inspected Overview
headings in earlier screenshots and re-ran Wishlist plus active-work UI tests;
it did not rerun Reduce Motion or the full Overview accessibility matrix.

## Selected screenshots

These are captures from the earlier presentation session's simulator runs, not
substitutes for runtime verification after future changes.

- [iPhone Library, light](screenshots/library-d/iphone-light.png)
- [iPhone Library, dark](screenshots/library-d/iphone-dark.png)
- [iPhone empty](screenshots/library-d/iphone-empty.png)
- [iPhone error](screenshots/library-d/iphone-error.png)
- [iPad Library, light](screenshots/library-d/ipad-light.png)
- [iPad Library, dark](screenshots/library-d/ipad-dark.png)
- [iPhone largest text](screenshots/library-d/iphone-large.png)
- [iPhone largest text, Books filter](screenshots/library-d/iphone-large-filtered.png)
- [Overview heading, light](screenshots/library-d/iphone-overview-light.png)
- [Overview heading, dark](screenshots/library-d/iphone-overview-dark.png)

## Limits and readiness

No live-backend, physical-device, spoken VoiceOver, or freeform iPad
multitasking window-resize test ran. System Reduce Motion was not repeated for
Library. Create, item detail chrome, editors, Notes, Randomizer, and photo
uploads were not redesigned. Search remains native `.searchable`; status
filtering keeps the full backend status lists rather than D's shortened
segments. There is still no end-to-end UI test that drives an editor save that
leaves the current filter or a page-2 record; those paths are covered by the
focused LibraryModel regressions above.

Library presentation and migration boundary fixes are ready to leave for Create.
The next smallest presentation step is migrating Create's sticker chrome to the
shared quiet treatment while preserving its existing destinations. Notes should
remain a separate, explicitly scoped functional implementation.
