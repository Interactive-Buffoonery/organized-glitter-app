# Organized Glitter apps

Organized Glitter is a tracking app for diamond painting and coloring. This
repository contains its native apps. The SwiftUI client for iPhone and iPad
lives in `ios/`. Other platforms may be added alongside it in the future.

At this time, this project is a WIP. This README will be updated as the app progresses. You can access the web version of the app at https://organizedglitter.app.

## Requirements

- Xcode 26 or newer
- XcodeGen 2.46 or newer
- iOS or iPadOS 18.0 or newer

Routine builds, tests, and interface review use iOS and iPadOS 26 simulators.
APIs newer than iOS 18 must stay behind availability checks.

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
operations or production configuration into this repository. `BackendContract.json` records the compatibility contract used by the native
client.

### Local configuration

Debug builds use `https://data.organizedglitter.app` by default.

To use a local PocketBase instead, copy the example and set a URL your device
or simulator can reach:

```sh
cd ios
cp Config/Debug.local.xcconfig.example Config/Debug.local.xcconfig
```

`Config/Debug.local.xcconfig` is gitignored. Keep credentials and private
infrastructure out of tracked files.

The tracked Release configuration intentionally points to `example.invalid`.
Official release builds receive their backend URL through the gitignored
`Config/Release.local.xcconfig`.

## Tests

Run the local preflight check from the repository root:

```sh
./ios/script/pre-pr.sh
```

Most tests run without a backend. Seeded PocketBase tests are opt-in and read
their URL and test credentials from environment variables.

## Project boundaries

- `ios/OrganizedGlitter/App` owns application setup, session state, and navigation.
- `ios/OrganizedGlitter/Networking` owns PocketBase requests and Keychain storage.
- Feature folders own their views and local state.
- `ios/OrganizedGlitter/Design` owns the native theme and reusable visual pieces.
- `ios/docs/architecture.md` documents data handling and release gates.
- `ios/docs/design.md` documents the Berry Cream design system.

The app keeps server records in memory. It doesn’t persist a record cache,
queue offline writes, or treat the client as the source of truth.

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
