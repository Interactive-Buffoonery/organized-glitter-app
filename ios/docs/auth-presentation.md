# Account-entry presentation

This refinement is stacked on native Apple sign-in PR #18. It preserves the
Berry Cream background, wordmark, provider readiness, and authentication paths.

- Primary actions are centered and capped at 280 points; provider choices at
  300 points. Forms have a 360-point reading width on iPad.
- Buttons retain at least 52-point heights and expand for larger text. Apple's
  native control has an explicit scaled height instead of an unbounded minimum.
- Google and Discord use their original marks, with email below the providers.
- Registration, sign-in, reset confirmation, reset requests, and verification
  requests share the same primary style and stable loading label.
- Account-switch prompts stack so long text does not compete with the action.

## Provider artwork

These are third-party trademarks, excluded from the repository's Apache-2.0
artwork license. They identify authentication options only.

- Google: original [G asset](https://developers.google.com/static/identity/images/g-logo.png),
  obtained from [Sign in with Google branding guidance](https://developers.google.com/identity/branding-guidelines).
  The original multicolor mark is retained on neutral white/dark surfaces.
- Discord: original black and white Clyde SVGs from the
  [official brand page](https://discord.com/branding), downloaded from the linked
  [black archive](https://cdn.discordapp.com/assets/content/aecd9009fd6a24c06c8ce71f6bb84463eaf7252bc5259022fb887b381a428250.zip)
  and [white archive](https://cdn.discordapp.com/assets/content/80af2c38f13b4a7d2cb3572e1220f6e958d3c3aedccc7c7d3ddc9832f6b3d725.zip).
  Geometry and fills are unchanged; the asset catalog chooses white in dark mode.

Provider logos are decorative within buttons whose full text supplies their
accessible name. No new third-party SDK is used.
