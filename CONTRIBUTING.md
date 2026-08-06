# Contributing to Organized Glitter

Thanks for helping with Organized Glitter!

## Before you start

- Check the open issues and pull requests for existing work.
- Open an issue before starting a large feature or structural change.
- Read `README.md`, `ios/docs/architecture.md`, and `BRAND.md`.
- Keep backend work in the backend repository. Don’t copy PocketBase schema,
  hooks, migrations, collection rules, or production operations here.
- Small, focused pull requests are much easier to review than a branch that changes several unrelated things.

## Build and test

Generate the project:

```sh
cd ios
xcodegen generate
```

Before opening a pull request, run the local preflight check:

```sh
./ios/script/pre-pr.sh
```

This checks the diff, then builds the app and runs the unit and UI tests on the
iPhone 17 simulator. To use another installed simulator, set `DESTINATION` to
an `xcodebuild` destination before running the script.

The app supports iOS and iPadOS 18.0 and newer. Routine development uses iOS
and iPadOS 26 simulators, but APIs newer than iOS 18 need availability checks.

Seeded backend tests are optional. Use disposable test accounts and records -
never use customer accounts or customer data.

## Code changes

- Use Swift 6 strict concurrency.
- Prefer Apple platform APIs over new dependencies.
- Keep feature state local and inject dependencies directly.
- Use `PocketBaseClient` as the concrete transport. Don’t add a protocol or
  repository layer for a single implementation.
- Treat cancellation as normal.
- Use partial updates and refresh after writes.
- Use native controls and include accessibility labels.
- Keep server records in memory. Don’t add offline writes or a persistent
  record cache.
- Match the existing indentation and formatting.

If `ios/project.yml` changes, run `xcodegen generate` from `ios/` and include the generated
Xcode project changes in the same pull request.

## Privacy and security

Never include any of these in code, tests, fixtures, logs, screenshots, issues,
or pull requests:

- Credentials, tokens, OAuth codes, or private keys
- Customer content or account details
- Email addresses or other personal information
- Private file URLs
- Production configuration or private infrastructure details
- Backend schema, hooks, migrations, collection rules, or operational records

Use obvious example values such as `example.test` and `test-token` in tests.
Report security problems privately using `SECURITY.md`.

## Pull requests

- Keep the change focused.
- Explain what changed and why.
- Include the smallest test that proves non-trivial behavior.
- Run relevant tests and `git diff --check`.
- Call out iOS 18 compatibility and accessibility considerations.
- Don’t include unrelated formatting or cleanup.
- Don’t post private backend links or internal planning context.

All changes land through pull requests. Commit messages use this format:

```text
<type>(<scope>): <imperative subject>
```

Use `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, or `perf` as
the type. Keep the subject at 50 characters or fewer, don’t end it with a
period, and don’t use emojis or co-author trailers.

## AI-assisted contributions

When using AI assisted coding tools, a human must own every contribution.

If you use AI while preparing a pull request:

- Read and understand what the code, docs, tests, and commands you submit
  actually do.
- Be ready to explain what changed and why without sending reviewers back to
  an AI transcript.
- Personally verify the behavior you claim is fixed or added.
- Disclose substantial AI assistance in the pull request body.
- Review AI-drafted summaries, test plans, comments, and replies before posting
  them.
- If an AI agent drafts the pull request body, it should ask the contributor
  how much assistance to disclose after they have reviewed and revised the
  work: `none`, `light`, `moderate`, or `substantial`.

Knowing AI was used gives us context when reviewing pull requests. The same quality bar applies either way: the
change should be clear, tested where practical, and small enough for a
maintainer to review with confidence.

Don’t let an autonomous agent open pull requests, push commits, post review
comments, or reply to maintainers without direct human approval and ownership
of the result. If a pull request looks like unreviewed generated work,
maintainers may close it without reviewing.

Don't ever submit AI-generated art or graphics. While AI is an useful development tool, this repository takes a hard stance against AI for creative work.

## License and branding

Contributions intentionally submitted to this repository are licensed under
Apache-2.0.

The Organized Glitter name, logo, app icon, screenshots, and official artwork
remain proprietary. Read `BRAND.md` before adding or changing branded assets.
Public forks must use their own name and artwork.

By opening a pull request, you confirm that you have the right to contribute
the submitted code, documentation, and assets under these terms.
