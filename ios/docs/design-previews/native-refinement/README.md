# Approved native refinement

Sarah approved `approved-light.png` and `approved-dark.png` on 2026-09-19.
These supersede the historical D layout for the six migrated working screens.
ADR 0001 still owns the Berry Cream palette/backgrounds. System tab behavior,
actual model values, and existing web semantics take priority over generated
image details. Preserve the five native destinations.

References were created with the built-in imagegen tool. They show synthetic
content and are visual guides, not executable screens or backend contracts.

The `design` fixture mirrors the openly licensed content in the shared
`example@organizedglitter.app` test account. Its images live in the debug-only
`Preview/FixtureAssets.xcassets`, which Release builds exclude. Other fixtures
use artwork drawn in code (`OverviewFixtureProtocol.artwork`). The explicit
missing-image fixture still returns 404. Never add kit product photos or other
licensed artwork.

Image credits:

- Diamond projects: Unsplash photos under the Unsplash License
  (https://unsplash.com/license). Summer Garden Blooms by Annie Spratt
  (`MRjuroFzfQw`), Misty Mount Rainier by Dave Hoefler (`UHFQPFt5-WA`), Monarch
  in the Garden by Aaron Burden (`XR3uGa4gXgE`), Golden-Eyed Tabby by Borna
  Bevanda (`6CwBxiekWcw`), Mirror Lake Reflections by Hayden Walker
  (`0SzZ5ttDrdE`), and San Diego Sunset by Braden Jarvis (`ih5Kq0XowwY`).
- Smithsonian Libraries Coloring Pages, Volume 2: Smithsonian Libraries
  (https://library.si.edu/event/coloring-pages-v-2).
- Exoplanet Travel Bureau Coloring Book: NASA/JPL-Caltech.
- Our Very Own Star: The Sun: NASA Goddard Space Flight Center; illustrations
  by Daniel Vong.
- NASA's Field Guide to Black Holes Coloring Book: NASA.
