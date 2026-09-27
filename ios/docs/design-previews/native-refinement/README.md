# Approved native refinement

Sarah approved `approved-light.png` and `approved-dark.png` on 2026-09-19.
These supersede the historical D layout for the six migrated working screens.
ADR 0001 still owns the Berry Cream palette/backgrounds. System tab behavior,
actual model values, and existing web semantics take priority over generated
image details. Preserve the five native destinations.

References were created with the built-in imagegen tool. They show synthetic
content and are visual guides, not executable screens or backend contracts.

Kit artwork and book covers are real product images, one imageset per
fixture file name (`design-yorkie-roses`, `design-book-0`, and so on), loaded
through the normal file-request path:

- Diamond Art Club:
  [Yorkie & Roses](https://www.diamondartclub.com/products/yorkie-roses)
  by Maryline Cazenave,
  [Beachside Gathering](https://www.diamondartclub.com/products/beachside-gathering-diamond-art-kit)
  by Thomas Kinkade Studios, and
  [Divine Descent](https://www.diamondartclub.com/products/divine-descent)
  by Margaret Morales.
- Hachette Heroes Mystery Colouring: Princesses, Family, Pixar, Classics.

Page photos use four unchanged illustration crops (Rapunzel, Snow White, Ariel,
and Mulan) from Hachette's official Princesses interior preview. No AI-generated
artwork is bundled in the sample data. Sample page numbers and progress remain
fictional; the source illustrations are solutions 29–32.

- [Publisher product page](https://www.hachette.fr/livre/coloriages-mysteres-disney-princesses-9782019457150/)
- [Original interior preview](https://media.hachette.fr/fit-in/1600x1600/contenuNumerique/968/757496-001-C.jpg?source=web)
- Downloaded 2026-09-27. Artwork: Disney; publisher: Hachette Heroes;
  illustrator: Jérémy Mariez.
- Crops retain the printed illustration borders and color keys; Rapunzel and
  Mulan are rotated upright. No generated
  fill, repainting, or other AI processing was used.

The older fictional test records reuse these product images. Unrecognized
fixture upload filenames use the Yorkie & Roses product image as a stand-in;
the explicit missing-image fixture still returns 404.

All fixture images live in the development-only `Preview/FixtureAssets.xcassets`
catalog, explicitly excluded from Release builds in addition to Xcode's
`DEVELOPMENT_ASSET_PATHS` setting. The historical generated design references
above are documentation only and are not loaded by the app.
