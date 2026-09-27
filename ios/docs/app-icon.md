# Sorted app icon

The approved artwork uses eight berry and lilac pieces and a pink sparkle on
navy (`#05051A`), deeper than the page background (`#151533`). It has no outer border in either light or dark mode. The square
grid is centered; the sparkle extends above it without moving the grid down.

## Assets

- `AppIcon.appiconset/AppIcon.png`: 1024px opaque square. iOS applies its own mask.
- `Logo.imageset/logo.png`: 512px rounded tile for in-app branding.
- `LaunchWordmark`: the separate Caveat text wordmark. It contains no old icon
  and retains its existing layout and appearance variants.

The Xcode project explicitly selects `AppIcon` as its app icon asset catalog.

## Regeneration

The editable SVG and export script live in the web repository:
[`docs/icons/app-icon.svg`](https://github.com/Interactive-Buffoonery/organized-glitter/blob/dev/docs/icons/app-icon.svg).
Run `node scripts/generate-app-icons.mjs` there with its documented development
dependencies, then copy the approved static exports:

| Web export | Native destination under `Resources/Assets.xcassets/` |
| --- | --- |
| `docs/icons/app-icon-1024.png` | `AppIcon.appiconset/AppIcon.png` |
| `public/images/logo.png` | `Logo.imageset/logo.png` |

There is no runtime or application-code dependency between the repositories.
Do not export the rounded logo as the home-screen icon, add transparent margins
to the square icon, or independently redraw the grid.

After replacement, build for iPhone and iPad and check the installed home-screen
icon. Check the PNG dimensions and ensure the square icon is fully opaque.
