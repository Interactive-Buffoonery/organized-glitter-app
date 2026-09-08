# Numbered section picker

Baseline: `96b07664d9f86a770cceb6aac7f1dfaed9df4780`.
Publication base: `717ee0c93efc038f8a4eba670f96dfb472c75d17`, including the
Library repeat-save fix. The focused checks were rerun after rebasing onto it.

The Randomizer tab now offers a local numbered-section picker. Enter positive
whole numbers separated by commas or whitespace, then pick or reroll. Duplicate
numbers receive one chance each. Editing the choices clears the old result.
Invalid input displays an error. VoiceOver announcements report errors and picks.
The native Berry Cream background, system text styles, and quiet button treatment
are retained, with scrolling and a readable maximum width on iPad.

The behavior follows the numbered-section part of web PR #185, merged in
`7d3991c5`, specifically `NumberSectionPicker.tsx` and its tests in
`DiamondSectionHelper.test.tsx`. Numbers use the same positive JavaScript safe
integer ceiling so the tool does not introduce incompatible values.

This is a standalone tool. It does not select projects, change project state,
save Next Up, or synchronize selections. The screen explains that picks are not
saved to a project. There are no backend requests, persistent storage, contract
changes, dependencies, or auth/library changes.

## Checks

Focused Swift Testing coverage includes separators, duplicate normalization,
empty and malformed input, overflow, the safe-integer boundary, repeated picks,
a single distinct choice, stale result clearing, error recovery, and preserving
the result when keyboard dismissal commits unchanged input. The UI tests caught
that last regression before the guard against unchanged input was added.

UI coverage checks labeled input, empty-input error, duplicate input, repeated
rerolls, the result's combined accessibility label, and largest Dynamic Type
action reachability. Screenshots are retained in the test result bundle.

On iOS 26.5, the iPhone 17 simulator passed seven Swift Testing tests (including
12 parameterized invalid-input cases) and both UI tests. The iPad (A16) simulator
also passed both UI tests. The test helper opens the native tab bar's Next
Page control when present, since large text can put Randomizer in its overflow.

The final run uses `xcodebuild test`, scheme `OrganizedGlitter`, isolated derived
data at `.derived-data/number-picker`, `-parallel-testing-enabled NO`, and
`-only-testing:OrganizedGlitterTests/NumberSectionPickerTests` plus
`-only-testing:OrganizedGlitterUITests/NumberSectionPickerUITests`. iPad runs select
only the UI suite. Screenshots cover regular result and largest Dynamic Type.

This is focused feature validation, not a full app test run or release gate.
VoiceOver announcement calls are implemented, but spoken output was not manually
audited with VoiceOver enabled. Dark appearance, physical devices, and an iOS 18
runtime were not exercised in this pass. No live backend is needed by this tool.
