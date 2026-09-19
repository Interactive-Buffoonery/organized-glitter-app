# Approved native refinement

Sarah approved `approved-light.png` and `approved-dark.png` on 2026-09-19.
These supersede the historical D layout for the six migrated working screens.
ADR 0001 still owns the Berry Cream palette/backgrounds. System tab behavior,
actual model values, and existing web semantics take priority over generated
image details. Preserve the five native destinations.

References were created with the built-in imagegen tool. They show synthetic
content and are visual guides, not executable screens or backend contracts.

`FixtureArtwork` is original synthetic artwork generated with the same built-in
tool for deterministic Debug UI review. The fixture loader selects a quadrant
for each craft through the normal file-request path. It is not user content.

`FixtureBookCovers` supplies four original portrait book covers in a 2-by-2
contact sheet: Botanical days, Small wonders, The secret woodland, and Garden
birds, in reading order. These were generated for the same fictional records
with botanical ink/watercolor art, quiet serif titles, and no marketing copy.
The fixture crops at the midpoint boundaries without stretching the covers.
Both atlases live in the development-only `Preview/FixtureAssets.xcassets`
catalog, explicitly excluded from Release builds in addition to Xcode's
`DEVELOPMENT_ASSET_PATHS` setting.

Fixture generation prompt:

> Generate a square 2-by-2 contact sheet of four ORIGINAL craft artworks for synthetic test fixtures in an iPhone diamond painting and coloring tracker. Exactly equal quadrants, edge-to-edge images, NO gutters, NO frames, NO captions, NO UI, NO typography. TOP LEFT: beautiful pink peonies and lilac flowers rendered as a flat finished diamond painting canvas, tiny realistic faceted square resin beads, viewed straight on so entire square composition is visible. TOP RIGHT: citrus lemons and white orange blossoms rendered as an entire finished diamond-art canvas with tiny faceted beads, straight on. BOTTOM LEFT: moonlit botanical garden colored-pencil coloring page on ivory paper, navy night sky and pale flowers with some uncolored ink linework; entire square illustration visible, no pencil objects. BOTTOM RIGHT: refined botanical coloring-book cover artwork, ivory paper, fine green fern stems and pale pink flowers around an empty central oval, NO words. Cohesive palette raspberry pink, lilac, natural green, navy; crafted tactile detail, sophisticated art, no glitter effects outside actual beads. Each quadrant stands alone and will be separately cropped at its exact quadrant edges by a debug fixture loader. This is original fictional test artwork, not user content or any existing copyrighted book cover.
