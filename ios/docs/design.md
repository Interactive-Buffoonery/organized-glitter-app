# Design system — "Berry Cream"

The iOS app ships one theme of its own, in a light and a dark variant. It does
**not** port the web application's Catppuccin themes — those stay on web. The
look is inspired by Pagebound's cheerful sticker aesthetic: soft gradient
backgrounds, pastel "sticker" cards with a crisp outline and offset hard
shadow, pill buttons, and Caveat display headers.

Canonical sources, in order:

1. `OrganizedGlitter/Design/Theme.swift` + `Theme+Flavors.swift` — the tokens.
2. This document — hex values and rules, kept in sync with the code.
3. `docs/mockups/theme-mockups.html` and `docs/mockups/berry-dark-options.html`
   — the approved HTML mockups the palette was chosen from (open in a browser).

The retained native palette and backgrounds are recorded in
[ADR 0001](adr/0001-retain-native-backgrounds.md). That decision takes
precedence over the D studio and standalone preview background treatments.

## Variants

- **Light — "Berry Cream."** Blush-to-lilac gradient, raspberry primary,
  pastel sticker cards.
- **Dark — "Glow Stickers."** Dark plum stage, but sticker cards keep the
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
| `background` | `#F8E9F6` | `#221D33` |
| `foreground` | `#46323E` | `#F2E6EE` |
| `card` | `#FDF5F8` | `#2C2438` |
| `cardForeground` | `#46323E` | `#F2E6EE` |
| `popover` | `#FDF5F8` | `#2F2740` |
| `popoverForeground` | `#46323E` | `#F2E6EE` |
| `primary` | `#D23C77` | `#F58BB5` |
| `primaryForeground` | `#FFFFFF` | `#3A1524` |
| `secondary` | `#F6DCE6` | `#342B42` |
| `secondaryForeground` | `#46323E` | `#F2E6EE` |
| `muted` | `#F3E4EC` | `#322940` |
| `mutedForeground` | `#765669` | `#B7A3B2` |
| `accent` | `#8535D4` | `#C9A2F9` |
| `accentForeground` | `#FFFFFF` | `#2A1F3A` |
| `destructive` | `#C93A4C` | `#F57A8A` |
| `destructiveForeground` | `#FFFFFF` | `#3A151C` |
| `border` | `#E5CDD9` | `#453A52` |
| `ring` | `#D23C77` | `#F58BB5` |

`accent` stays the brand purple (`#8535D4`) from the original Organized
Glitter identity and the app icon.

## Background gradient

Applied top-to-bottom on every page (`Theme.backgroundGradient`), including
list screens via `.themedScrollBackground()`. Never leave a screen on the
stock grouped-list grey.

| Stop | Light | Dark |
| --- | --- | --- |
| Top | `#FDEEF3` | `#251A24` |
| Middle | `#F8E9F6` | `#221D33` |
| Bottom | `#E7DEFA` | `#1D1B2E` |

## Sticker surfaces (shared between variants)

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

## Sticker chrome

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
