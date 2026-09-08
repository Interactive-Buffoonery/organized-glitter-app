# ADR 0001: Retain the native palette and backgrounds

Status: Accepted by Sarah

## Context

The UI rebuild adopts the selected D direction and its layout refinements.
The active native checkout already contains uncommitted Berry Cream theme
work. Sarah clarified that these native colors and backgrounds are the ones
to retain. This supersedes the earlier conversation decision to adopt the
D studio's deeper diagonal gradient.

## Decision

Keep the current native light and dark palettes in `Theme+Flavors.swift`.

- Light: a top-to-bottom gradient from `#FDEEF3` through `#F8E9F6` to
  `#E7DEFA`.
- Dark: an opaque navy base, `#05051A`, with a purple radial glow at the
  bottom. Its stops are `#5C27B5` at 0, `#371475` at 0.38, and transparent
  at 0.73. The center is `(0.56, 1.0)` and the radius is 0.55 times the
  longer view dimension.
- Keep `Theme.themedBackground` as the shared background entry point.

Do not replace these backgrounds with either the D studio's diagonal
full-screen gradient or the standalone refinement's flat ordinary screens.
D's layout, action hierarchy, and form refinements can be adopted while
preserving this palette. This decision does not require retaining the old
sticker outlines, shadows, or layout.

## Consequences

Preserve the existing theme work during cleanup. Retain the test covering
the native dark glow. Check both appearances, readable contrast, and
background continuity on iPhone and iPad as the presentation is rebuilt.

The design previews are interaction references, not backend contracts.
No backend behavior changes follow from this decision.
