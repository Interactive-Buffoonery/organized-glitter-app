# Design system — "Berry Cream"

The iOS app uses the native Berry Cream palette in light and dark appearances.
[ADR 0001](adr/0001-retain-native-backgrounds.md) controls the palette and
screen backgrounds. The Shelf redesign (Option B in
[redesign-options.html](mockups/redesign-options.html), audit in
[redesign-audit.md](mockups/redesign-audit.md)) is the current direction.

## Shelf

- **Shell.** Home, Library, and on iOS 26 a `Tab(role: .search)`. iOS 18
  searches inside Library with `.searchable`. Account opens from the Home
  toolbar avatar. Create is the toolbar `+` `CreateMenu` on Home and Library.
  The randomizer code stays but has no tab.
- **iPad.** The `.sidebarAdaptable` `TabView` lists one sidebar row per craft
  in a `TabSection("Library")`. The single Library tab shows only in the tab
  bar, so there is no nested `NavigationSplitView`.
- **Library.** A covers grid under a row of status chips (All plus every
  backend status). Sort is a toolbar menu next to `+`. A craft with nothing in
  it hides chips and sort and shows one "Add your first kit" (or book) prompt
  that opens the editor.
- **Home.** A Continue carousel of in-progress covers, most recently logged
  first within the fetched records (`/api/notes/latest`, falling back to
  `updated`), each diamond cover
  carrying a glass Log button. "Up next from your stash" shows Kitted up then
  In stash covers. A single "N finished this month" row opens Completed.
  Section titles open the matching Library filter; a menu picks the craft when
  both are enabled.
- **Detail.** A centered hero cover over the title and credits, then a status
  `Menu` beside the prominent Log button. Diamonds show a spec strip (size,
  drill, diamonds, started) that turns into rows at accessibility sizes, a
  progress contact sheet, and a Details card (company, artist, kit, dates,
  tags, source link, notes as plain text). Books show pages as a contact sheet
  with a status glyph per page. Detail scroll content uses a plain `VStack`;
  a `LazyVGrid` inside a `LazyVStack` loops layout at AX5.
- **Covers.** `CoverArtwork` draws every cover in a 4:5 frame, filled and
  clipped. Records without art get a `GeneratedCover`: a Berry Cream gradient
  seeded by record id, the title in Caveat, and a craft glyph.
- **Titles.** One Caveat large title per screen through
  `UINavigationBarAppearance`. No in-content page headers.
- **Statuses.** `DiamondStatus`, `BookStatus`, and `PageStatus` carry the label
  and SF Symbol for every select value on the backend.

## Current design reference

The current six-screen references are in
[native refinement](design-previews/native-refinement/README.md). Generated
boards guide hierarchy and composition; real model values and native platform
behavior take precedence over their illustrative labels and tab bars.

## Historical D reference

The earlier Overview and Library migration used
`Interactive-Buffoonery/organized-glitter`,
branch `design/ios-mockup-studio`, revision
`0135e6d3caa73ea01224bda27c8e0abbb954fd19`:

- `docs/design-previews/ios-mockup/README.md`
- `docs/design-previews/ios-mockup/client/phone.tsx` and `client/styles.ts`
- `docs/design-previews/organized-glitter-ios.html`, the standalone refinement
  named by the README, including its compact actions and Notes refinements.

That historical preview is D-only. A–C comparisons and the successive treatments
in `STYLE.md` are historical experiments. Neither the studio's diagonal
background nor the standalone's flat ordinary screens supersedes ADR 0001.
Prototype saving, Notes, sharing, and other simulated actions are not native
implementation contracts.

## Historical native refinement

Verification of the earlier Overview and Library layout is recorded in
[Native refinement validation](native-refinement-validation.md).
That Overview used a single system heading, compact craft selection, artwork rows,
See all in progress, Wishlist, and Completed shortcuts, then its count summary.
Library kept peer craft segments on iPhone and the craft sidebar on iPad. Search,
status, and sort operated on the server; the grid showed title and written status,
with page counts for books. Company and artist credits remained available in detail.

Overview and Library share the same interactive detail destination. Diamond
photos are dated progress-note images. Coloring-page photos append to the
existing multi-file field. Book details query their own pages and edit the book's
page count through the existing editor; they do not directly create page records.

## Historical migration evidence

Earlier runtime checks and screenshots are recorded in
[Overview validation](overview-validation.md),
[Library validation](library-validation.md), and
[Account entry validation](account-entry-validation.md).

At that revision, Library used peer craft
segments (Diamond art / Books / Pages), native search, a quiet status menu,
and an artwork-led two-column gallery. Captions then preferred company,
publisher, or parent book title. Create stays in the scroll content, not the
navigation bar.
iPad keeps a craft sidebar and opens item details on the content stack.
Artwork uses `RecordArtwork` and `PocketBaseClient.fileURL`, with a shared
missing/failed fallback. `listingIdentity` includes a handoff epoch so
returning to the same craft's Wishlist clears search and reloads the
unsearched listing without `apply` starting a second competing load.

The earlier Overview reused `PageHeader` and `SectionHeader`, `QuietActionStyle`
and `ActiveProjectRow`, and uses the quiet presentation of `StatusBadge`.
Rows show uncropped project artwork or the first nonempty page photo through
`PocketBaseClient.fileURL`; missing and failed images have a neutral fallback.
Artwork is record-driven and replaceable. `pageSecondaryForeground` uses existing foreground text in dark mode to meet
contrast over the brightest glow; it uses muted text in light mode. No palette
values change. Rows have no sticker outline, hard
shadow, or decorative icon tile. Status retains its written label and icon.
Large accessibility text changes rows to a vertical layout and craft selection
to a native menu. Quiet controls have no custom movement or animation.

The earlier Overview placed craft selection and active work before a compact
count summary.
Its background belongs to the scroll viewport and extends through safe areas,
not the content stack, so content height does not determine the glow geometry.
Content has a readable maximum width on iPad while the background fills the screen.
Loading, retry, empty, refresh, and detail navigation remain available; failed
refreshes also show an error while retaining in-memory rows.

See all in progress, Wishlist, and Completed open the existing Library tab
with the selected craft's matching filter and clear old search text. The menus
follow enabled Library crafts. A combined Wishlist screen and native Notes feed
are follow-up work; Overview has no placeholder Notes control. The existing
per-craft limit of five recently updated active records remains unchanged; the
summary uses server totals.

Account entry was migrated against the same studio revision while keeping
ADR 0001 backgrounds. The system launch screen uses a solid brand
`LaunchBackground` with a `LaunchWordmark` asset drawn where Welcome places its
wordmark. While session restore runs, Welcome's layout stands in as the splash:
its three sparkles twinkle in place of a spinner, the actions stay hidden, and
the themed background fades in over the flat launch color. Nothing moves on the
way to Welcome. `script/render-launch-wordmark.swift` redraws the launch asset
from the shared `BrandWordmarkArt`. `AccountEntryLayout` owns the padding,
button heights, action spacing, and wordmark size used by Welcome and derives
the renderer offset and canvas from them. Sparkle geometry lives only in
`BrandWordmarkArt`; regenerate the PNGs after changing these metrics. The static
launch image targets the default text size; Dynamic Type can resize the live UI.
Signed-out users land on Welcome (wordmark
with still sparkles above Create account and Sign in) with no authenticated
tabs. `WelcomeView` owns the
signed-out `NavigationStack`. Method selection offers Continue with email only;
Apple, Google, and Discord stay out until a native OAuth path and provider
continuity land. Email sign-in, registration, password-reset
request/confirmation, and verification request use quiet auth controls instead
of sticker pills. See
[account-entry validation](account-entry-validation.md).

The sticker system (`StickerCard`, `IconBadge`, `PillButtonStyle`, and their
tokens) was removed with the Create tab.

## Variants

- **Light — "Berry Cream."** Blush-to-lilac gradient, raspberry primary.
- **Dark — "Berry Cream after dark."** Deep navy stage with a purple radial
  bloom rising from the bottom.

`ThemeFlavor` is `system` / `light` / `dark`. Retired Catppuccin raw values
(from older builds or the account's `theme_preference`) fail to parse and fall
back to the device preference — see `AppModel.applyThemePreference`.

## Semantic tokens

| Token | Light | Dark |
| --- | --- | --- |
| `background` | `#F8E9F6` | `#05051A` |
| `foreground` | `#46323E` | `#F7F2F7` |
| `card` | `#FDF5F8` | `#141028` |
| `cardForeground` | `#46323E` | `#F7F2F7` |
| `popover` | `#FDF5F8` | `#0F0B28` |
| `popoverForeground` | `#46323E` | `#F7F2F7` |
| `primary` | `#D23C77` | `#F58AB5` |
| `primaryForeground` | `#FFFFFF` | `#381423` |
| `secondary` | `#F6DCE6` | `#0F0B28` |
| `secondaryForeground` | `#46323E` | `#F7F2F7` |
| `muted` | `#F3E4EC` | `#1C1636` |
| `mutedForeground` | `#765669` | `#BEB1C3` |
| `accent` | `#8535D4` | `#CAA4F9` |
| `accentForeground` | `#FFFFFF` | `#05051A` |
| `destructive` | `#C93A4C` | `#EA3E3E` |
| `destructiveForeground` | `#FFFFFF` | `#F7F2F7` |
| `border` | `#E5CDD9` | `#37304B` |
| `ring` | `#D23C77` | `#F58AB5` |

`accent` stays the brand purple (`#8535D4`) from the original Organized
Glitter identity and the app icon.

## Page background

Painted behind every screen via `Theme.themedBackground`, including list
screens through `.themedScrollBackground()`. Never leave a screen on the
stock grouped-list grey.

- **Light** uses a top-to-bottom blush-to-lilac `backgroundGradient`:

| Stop | Light |
| --- | --- |
| Top | `#FDEEF3` |
| Middle | `#F8E9F6` |
| Bottom | `#E7DEFA` |

- **Dark — "Berry Cream after dark"** paints a flat navy base (`#05051A`) with
  a purple radial bloom rising from the bottom. The bloom is a circular
  `RadialGradient` centered at `(0.56, 1.0)` with `endRadius` 0.55 × the
  longer screen dimension, approximating the web app's elliptical
  `radial-gradient(... at 56% 116%)` bloom:

| Stop | Location | Color |
| --- | --- | --- |
| 0 | `0.0` | `#5C27B5` |
| 1 | `0.38` | `#371475` |
| 2 | `0.73` | transparent |

## Typography

- **Caveat** (bundled) is the large-title face, set once per screen through
  `UINavigationBar.applyCaveatLargeTitles()` and scaled with Dynamic Type. It
  is also the generated-cover title. Never use Caveat for body text, labels, or
  buttons.
- Everything else is the system font with Dynamic Type styles.

## Iconography

SF Symbols only — no emoji, no bundled icon fonts. The web app uses Lucide;
pick the SF Symbol closest to the web app's Lucide choice so the two apps
read as siblings. Established mappings:

| Concept | Web (Lucide) | iOS (SF Symbol) |
| --- | --- | --- |
| Overview / home | `Home` | `house` |
| Library / dashboard | `LayoutDashboard` | `square.grid.2x2` |
| Create | `Plus` | `plus` |
| Randomizer | `Shuffle` | `shuffle` |
| Account | — | `person.crop.circle` |
| Diamond project | `Gem` | `diamond` |
| Coloring | `Palette` | `paintpalette` |
| Wishlist | `Heart` | `heart.circle.fill` |
| Completed | `CheckCircle` | `checkmark.circle.fill` |
| Archived / destashed | `Archive` | `archivebox.circle.fill` |
| In progress | — | `play.circle.fill` |
| On hold | — | `pause.circle.fill` |

If a pixel-exact match with web ever becomes a requirement, Lucide ships SVGs
that can be imported into the asset catalog as template symbol images — not
worth the Dynamic Type / weight-matching loss today.

## Accessibility rules (carried over from the original design contract)

- Color is never the only signal: status always pairs an icon with its
  written label (`StatusBadge`).
- Rows and cards combine into single accessibility elements where the parts
  read as one thing.
- Motion uses `Theme.motion` (ease-out-quart, 0.24 s) — no bounce, no elastic.
