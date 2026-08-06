# AGENTS.md

## Product

Organized Glitter is publicly distributed through the App Store. Each user’s
craft-project library and files are private. Read `README.md` and
`ios/docs/architecture.md` before changing application structure or backend behavior.

## Hard rules

- Support iPhone and iPad from iOS 18.0.
- Use iOS and iPadOS 26 simulators for routine builds, tests, and UI review.
- Guard APIs newer than iOS 18 with availability checks.
- Keep PocketBase as the only backend and identity system.
- Never merge accounts by email or reassign records on the client.
- Keep server data in memory. Do not add offline writes or a persistent record
  cache.
- Use Apple platform APIs before third-party dependencies.
- Never log credentials, auth tokens, OAuth codes, user content, private file
  URLs, email addresses, or other PII.
- Do not copy TypeScript, PocketBase hooks, migrations, or schema ownership into
  this repository.
- Backend changes must land in `Interactive-Buffoonery/organized-glitter` first
  and remain compatible with the web application and older iOS releases.
- Do not edit `ios/BackendContract.json` until the referenced backend revision has
  been verified.

## Commands

- Regenerate the Xcode project: `cd ios && xcodegen generate`
- Build: use XcodeBuildMCP, or
  `cd ios && xcodebuild -project OrganizedGlitter.xcodeproj -scheme OrganizedGlitter -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Test: use XcodeBuildMCP, or the matching `xcodebuild test` command.

## Swift

- Use Swift 6 strict concurrency.
- Prefer `@State`, `@Binding`, `@Observable`, and `@Environment`.
- Keep feature state local and inject feature dependencies explicitly.
- `PocketBaseClient` is the concrete transport. Do not add a protocol with one
  implementation or a generic repository layer.
- Treat task cancellation as normal.
- Use partial updates and refresh after writes.
- Use role-appropriate native controls and provide accessibility labels.

## Git

- All changes land through pull requests.
- Use imperative commit messages without emojis or co-author trailers.
- Preserve unrelated work and stage explicit paths.
