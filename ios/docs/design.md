# Design system — "Berry Cream"

The iOS app uses the native Berry Cream palette in light and dark appearances.
[ADR 0001](adr/0001-retain-native-backgrounds.md) controls the palette and
screen backgrounds. The selected D direction controls the new presentation:
artwork-led content, quiet actions, clear headings, and native interactions.

## Current design reference

Overview was migrated against `Interactive-Buffoonery/organized-glitter`,
branch `design/ios-mockup-studio`, revision
`0135e6d3caa73ea01224bda27c8e0abbb954fd19`:

- `docs/design-previews/ios-mockup/README.md`
- `docs/design-previews/ios-mockup/client/phone.tsx` and `client/styles.ts`
- `docs/design-previews/organized-glitter-ios.html`, the standalone refinement
  named by the README, including its compact actions and Notes refinements.

The current preview is D-only. A–C comparisons and the successive treatments
in `STYLE.md` are historical experiments. Neither the studio's diagonal
background nor the standalone's flat ordinary screens supersedes ADR 0001.
Prototype saving, Notes, sharing, and other simulated actions are not native
implementation contracts.

## Migration status

Runtime checks and current screenshots are recorded in
[Overview validation](overview-validation.md),
[Library validation](library-validation.md), and
[Account entry validation](account-entry-validation.md).

Library was migrated against the same studio revision. iPhone uses peer craft
segments (Diamond art / Books / Pages), native search, a quiet status menu,
and an artwork-led two-column gallery. Captions prefer company, publisher, or
parent book title. Create stays in the scroll content, not the navigation bar.
iPad keeps a craft sidebar and opens item details on the content stack.
Artwork uses `RecordArtwork` and `PocketBaseClient.fileURL`, with a shared
missing/failed fallback. `listingIdentity` includes a handoff epoch so
returning to the same craft's Wishlist clears search and reloads the
unsearched listing without `apply` starting a second competing load.

Overview now reuses `PageHeader` and `SectionHeader`, adds `QuietActionStyle`
and `ActiveProjectRow`, and uses the quiet presentation of `StatusBadge`.
Rows show uncropped project artwork or the first nonempty page photo through
`PocketBaseClient.fileURL`; missing and failed images have a neutral fallback.
Artwork is record-driven and replaceable. `pageSecondaryForeground` uses existing foreground text in dark mode to meet
contrast over the brightest glow; it uses muted text in light mode. No palette
values change. Rows have no sticker outline, hard
shadow, or decorative icon tile. Status retains its written label and icon.
Large accessibility text changes rows to a vertical layout and craft selection
to a native menu. Quiet controls have no custom movement or animation.

Overview places craft selection and active work before a compact count summary.
Its background belongs to the scroll viewport and extends through safe areas,
not the content stack, so content height does not determine the glow geometry.
Content has a readable maximum width on iPad while the background fills the screen.
Loading, retry, empty, refresh, and detail navigation remain available; failed
refreshes also show an error while retaining in-memory rows.

Wishlist opens the existing Library tab with the selected craft's wishlist
filter and clears old search text. The menu follows enabled Library crafts.
A combined Wishlist screen and native Notes feed are follow-up work; Overview
has no placeholder Notes control. The existing per-craft limit of five recently
updated active records remains unchanged; the summary uses server totals.

Account entry was migrated against the same studio revision while keeping
ADR 0001 backgrounds. The system launch screen uses a solid brand
`LaunchBackground`. The in-app restoration splash shows the Caveat wordmark
only while session restore runs. Signed-out users land on Welcome (wordmark,
Create account, Sign in) with no authenticated tabs. Email sign-in,
registration, password-reset request/confirmation, and verification request
use quiet auth controls instead of sticker pills. Apple, Google, and Discord
method buttons stay out until provider continuity and native OAuth work land;
see account-entry validation for the dependency list.

Other authenticated screens still use legacy sticker surfaces, `StickerCard`,
`IconBadge`, and `PillButtonStyle`. Their tokens and behavior remain until
those screens are migrated. The old Overview metric view, `LibraryItemRow`,
and unused surface-placement options on the Library row and status badge were
removed after checking references. `IconBadge` stays because Create still uses
it. The sections below describe both the retained palette and remaining legacy
chrome.

## Variants

- **Light — "Berry Cream."** Blush-to-lilac gradient, raspberry primary,
  pastel sticker cards.
- **Dark — "Berry Cream after dark" (Glow Stickers).** Deep navy stage with a
  purple radial bloom rising from the bottom. Legacy sticker cards keep the
  *light-mode pastel fills* with dark text — bright stickers on a dark
  scrapbook page. This is a deliberate contract: the five surface fills and
  their text colors are shared between variants, so there is exactly one
  pastel set to maintain and sticker text is always dark.
  `ThemeTests.stickerSurfacesAreSharedBetweenVariants` enforces it.

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

## Legacy sticker surfaces (shared between variants)

Cycled by index via `theme.accentSurface(i)`; indices wrap.

| Index | Name | Hex |
| --- | --- | --- |
| 0 | Strawberry | `#FBD0DD` |
| 1 | Lilac | `#ECD6FA` |
| 2 | Mint | `#CDEEDD` |
| 3 | Periwinkle | `#D3DEFB` |
| 4 | Butter | `#FDEAB8` |

Text on any sticker surface: `surfaceForeground` `#46323E`, secondary text
`surfaceMutedForeground` `#765669` — in **both** variants (the fills stay
light in dark mode, so the text stays dark).

## Legacy sticker chrome

| Token | Light | Dark |
| --- | --- | --- |
| `stickerOutline` | `#3A2531` | `#2F2029` |
| `stickerShadow` | `#3A2531` @ 85% | `#000000` @ 85% |
| `pillFill` | `#FBD8B8` | `#FBD8B8` |
| `pillForeground` | `#4D3016` | `#4D3016` |

Geometry (in `Theme.Sticker` / `Theme.Radius`): outline 1.5 pt, shadow offset
(2.5, 3.5) with **zero blur** (the hard offset is the look), sticker corner
radius 20 pt. Pressing a pill button collapses the shadow and shifts the pill
into it (`PillButtonStyle`).

Component: `.stickerCard(index)` supplies the current pastel card treatment.

## Typography

- **Caveat** (bundled, `Font.caveat(size:relativeTo:)`) is the signature
  display face: the page H1 (`PageHeader`, 40 pt) and section headers. Never
  for body text, labels, or buttons.
- Everything else is the system font with Dynamic Type styles.

## Iconography

SF Symbols only — no emoji, no bundled icon fonts. The web app uses Lucide;
pick the SF Symbol closest to the web app's Lucide choice so the two apps
read as siblings. Established mappings:

| Concept | Web (Lucide) | iOS (SF Symbol) |
| --- | --- | --- |
| Overview / home | `Home` | `house` |
| Library / dashboard | `LayoutDashboard` | `square.grid.2x2` |
| Create | `Plus` | `plus.circle.fill` |
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
- Text on sticker surfaces uses `surfaceForeground` (≥ WCAG AA on all five
  fills).
- Rows and cards combine into single accessibility elements where the parts
  read as one thing.
- Motion uses `Theme.motion` (ease-out-quart, 0.24 s) — no bounce, no elastic.
