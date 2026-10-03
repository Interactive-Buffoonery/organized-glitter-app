# Organized Glitter apps

Organized Glitter is a tracking app for diamond painting and coloring. This
repository contains the source code for its native apps. 

The SwiftUI client for iPhone and iPad
lives in `ios/`. Other platforms may be added alongside it in the future.

At this time, this project is very, very much a work in progress. This README will be updated as the app progresses. You can access the web version of the app at [https://organizedglitter.app](https://organizedglitter.app), and you can find updates on the progress of both the web and mobile apps at [https://organizedglitter.app/updates/](https://organizedglitter.app/updates/).

## Requirements

- Xcode 26 or newer
- XcodeGen 2.46 or newer
- iOS or iPadOS 26.0 or newer

Local tests also require Python 3 and an installed iOS 26 simulator runtime
with at least one iPhone and one iPad simulator. Select the full Xcode developer
directory with `xcode-select`; Command Line Tools alone cannot run these tests.

Routine builds, tests, and interface review use iOS and iPadOS 26 simulators.
APIs newer than iOS 26 must stay behind availability checks.

## Build the app

Generate the Xcode project, then open it:

```sh
cd ios
xcodegen generate
open OrganizedGlitter.xcodeproj
```

Or build directly for the routine simulator:

```sh
cd ios
xcodebuild \
  -project OrganizedGlitter.xcodeproj \
  -scheme OrganizedGlitter \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Simulator builds don’t need an Apple development team. Device and App Store
signing values are supplied privately and aren’t tracked in Git.

## Backend

Organized Glitter uses PocketBase for both data and identity. The backend remains responsible for schema, collection rules, hooks,
migrations, backups, recovery, and production deployment. Don’t copy those
operations into this repository. `BackendContract.json` records the compatibility contract used by the native
client.

### Local configuration

Debug and Release builds use `https://data.organizedglitter.app` by default.
That hostname is public application config, not a secret.

To point a local checkout at another PocketBase (for example
`http://127.0.0.1:8090`), copy the matching example. Those `*.local.xcconfig`
files are gitignored overrides; they are not how the shipped app learns its
backend.

```sh
cd ios
cp Config/Debug.local.xcconfig.example Config/Debug.local.xcconfig
```

## Tests

Run the local pre-PR check from the repository root:

```sh
./ios/script/pre-pr.sh
```

This runs on your Mac, without using GitHub Actions. The script checks whitespace
with `git diff --check`, regenerates the Xcode project, then runs three suites
sequentially:

1. Unit tests on an iPhone simulator.
2. Fixture UI tests on an iPhone simulator.
3. Fixture UI tests on an iPad simulator.

The script selects available iOS 26 simulators and prints their names, runtime
versions, and IDs. To use specific simulators, get their IDs with
`xcrun simctl list devices available` and pass both overrides:

```sh
IPHONE_SIMULATOR_ID='<iPhone simulator UUID>' \
IPAD_SIMULATOR_ID='<iPad simulator UUID>' \
./ios/script/pre-pr.sh
```

Each override is optional, but must identify an available device of the matching
family running iOS 26. The earlier `DESTINATION` override is replaced by these
device-specific variables. Use simulators that other test runs are not using.

Each run saves separate logs and `.xcresult` bundles under
`ios/.derived-data/pre-pr/run.*`. UI suites can take several minutes; use
`tail -f` on the printed log path to watch progress. The command prints passed,
failed, and skipped test counts for each suite, plus skipped UI test names from
the logs. Open a result bundle in Xcode for details. A failed suite does not
prevent the remaining suites from running; the command exits unsuccessfully if
any suite fails or has
no passing tests. Missing prerequisites stop the command before testing.

The routine gate uses local fixtures and excludes the seeded PocketBase tests,
even if their opt-in flag is set. Those integration tests require a separate run
against an isolated backend with disposable test accounts and private local
configuration. Never use production accounts or commit test credentials.

Fixtures use fictional records and drawn artwork, and the app has no
sample-data mode. To review the app with real content, sign in to the shared
`example@organizedglitter.app` account. Its password is shared privately; never
commit it.

Dedicated screenshot captures, system Reduce Motion checks, accessibility
detail captures, and seeded photo-picker checks remain opt-in. Device-specific
tests also skip on the other device family. A passing routine run does not mean
these skipped checks passed. Record the local suite results and relevant skips
in the PR's Verification section. For UI changes, also review iPhone and iPad
layouts, Dynamic Type, and accessibility, and attach relevant screenshots.

## Project boundaries

- `ios/OrganizedGlitter/App` owns application setup, session state, and navigation.
- `ios/OrganizedGlitter/Networking` owns PocketBase requests and Keychain storage.
- Feature folders own their views and local state.
- `ios/OrganizedGlitter/Design` owns the native theme and reusable visual pieces.
- `ios/docs/architecture.md` documents data handling and release gates.
- `ios/docs/design.md` documents the Berry Cream design system.
- Cross-platform audits and roadmap planning live in Sarah’s Obsidian vault.
  [Planning references](ios/docs/audits/web-dev-feature-parity.md) preserve the
  former document paths and point to the current comparison.

The app keeps downloaded records and pending edits in a private SwiftData
library scoped to the PocketBase server and account. Existing project, book,
and page metadata and status edits can be saved offline and later synchronized;
PocketBase remains authoritative for shared data. Previously viewed artwork
may be stored in a bounded private cache. New records, deletion, note
submissions, file uploads, taxonomy changes, account settings, and book page
counts still require connectivity. Sign-out drains active saves, asks before
discarding pending edits, and removes that account’s local library and artwork;
interrupted cleanup finishes before another account can sign in.

The mobile sync backend must be deployed before this native build is released.
See [`ios/docs/offline-library.md`](ios/docs/offline-library.md) for the contract,
security boundaries, supported operations, and validation.

## Security and privacy

Don’t put credentials, tokens, customer content, private file URLs, email
addresses, or other personal information in source, logs, screenshots, tests,
issues, or pull requests.

Private-file access, account deletion, and universal-link confirmation are
backend-first App Store release blockers. More detail lives in
[`ios/docs/architecture.md`](ios/docs/architecture.md).

## License and brand

The source code is available under the
[Apache License 2.0](LICENSE). Contributions intentionally submitted to this
project are licensed on the same terms.

The Organized Glitter name, logo, app icon, screenshots, and official artwork
remain proprietary. Forks intended for public distribution must use their own
name and artwork. See [`BRAND.md`](BRAND.md) for the full terms.

The bundled Caveat font uses the SIL Open Font License included at
`ios/OrganizedGlitter/Resources/Fonts/OFL.txt`.
