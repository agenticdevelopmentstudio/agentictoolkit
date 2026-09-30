<!-- leaf: implement-window-matching/heuristics · source: window-matching-heuristics.md -->

**Rules** (cite as `implement-window-matching/heuristics#<slug>`):

- `heuristic-shape` MUST
- `heuristic-sendable` MUST
- `heuristic-pure` MUST
- `nil-means-no-pattern` MUST
- `empty-title-nil` MUST
- `default-strategy-substring` MUST
- `default-fingerprint-pattern` MUST
- `trim-spaces-and-tabs-only` MUST
- `pattern-case-preserved` MUST
- `separator-set` MUST
- `separator-first-match-wins` MUST
- `separator-components-trimmed` MUST
- `separator-absent-single-component` MUST
- `separator-hyphen-not-split` MUST
- `xcode-identity` MUST
- `xcode-first-component` MUST
- `xcode-no-separator-whole-title` MUST
- `xcode-empty-first-component-nil` MUST
- `warp-identity` MUST
- `warp-requires-hyphen-separator` MUST
- `warp-remainder-after-first-separator` MUST
- `warp-strip-dirty-indicator` MUST
- `warp-strip-branch` MUST
- `warp-path-last-component` MUST
- `warp-root-path-nil` MUST
- `warp-plain-remainder` MUST
- `brave-identity` MUST
- `brave-strip-suffix` MUST
- `brave-bare-app-name-nil` MUST
- `brave-fallback-whole-title` MUST
- `brave-suffix-case-sensitive` MUST
- `vscode-identity` MUST
- `vscode-generic-titles` MUST
- `vscode-single-component` MUST
- `vscode-generic-last-returns-first` MUST
- `vscode-filename-first-prefers-last` MUST
- `vscode-default-first` MUST
- `vscode-filename-test` MUST
- `terminal-identity` MUST
- `terminal-strategy-app-only` MUST
- `terminal-second-component` MUST
- `terminal-strip-one-dash` MUST
- `terminal-empty-second-nil` MUST
- `terminal-single-component` MUST

# Window Matching Heuristics

## Overview

Window Matching Heuristics are the five built-in `AppHeuristic` conformers
that ship with AgenticToolkit's system-window matching: `XcodeHeuristic`,
`WarpHeuristic`, `BraveHeuristic`, `VSCodeHeuristic` and `TerminalHeuristic`.
Each one knows the window-title format of one application family and turns a
raw window title into the stable, identifying part of it — a project name, a
workspace name, a page title, a directory, or a running command — or `nil`
when no useful pattern can be extracted.

They are pure, stateless value types. `HeuristicRegistry.builtInHeuristics`
registers them (in the order Xcode, Warp, Brave, VS Code, Terminal) and looks
one up by the window's owning app name; `SystemWindowMatcher` then calls
`fingerprintPattern(for:)` when it fingerprints a window and
`extractPattern(from:)` when it scores a live window against a stored
fingerprint. Use this recipe to port the title-parsing rules; the registry,
the custom user rules (`CustomHeuristic`) and the matcher's scoring are
outside it.

The shared pieces the heuristics build on are the `AppHeuristic` protocol
(with its default `recommendedStrategy` and `fingerprintPattern(for:)`) and
the `HeuristicTitleParser` helper that splits a title on the em-dash or
en-dash separator.

## Behavioral Requirements

### Shared contract (`AppHeuristic`)

- **heuristic-shape**: Every heuristic MUST expose a `name` (a user-visible display name), an `appNames` list (the owning-app names it applies to), an `extractPattern(from:)` operation taking a raw title `String` and returning an optional `String`, a `recommendedStrategy` of type `MatchStrategy`, and a `fingerprintPattern(for:)` operation returning an optional `(pattern: String, strategy: MatchStrategy)` pair.
- **heuristic-sendable**: Every heuristic MUST be `Sendable`; the `AppHeuristic` protocol inherits `Sendable`, and each built-in is a struct whose only stored properties are `let` constants.
- **heuristic-pure**: `extractPattern(from:)` MUST return the same result for the same title on every call, with no side effects (no I/O, no logging, no stored state), so it MAY be called from any thread or task concurrently.
- **nil-means-no-pattern**: `extractPattern(from:)` MUST return `nil`, never an empty string, when it cannot extract a useful pattern; no built-in throws or reports an error.
- **empty-title-nil**: Every built-in heuristic MUST return `nil` for the empty title `""`.
- **default-strategy-substring**: A heuristic that does not override `recommendedStrategy` MUST report `MatchStrategy.appAndTitleSubstring`; `XcodeHeuristic`, `WarpHeuristic`, `BraveHeuristic` and `VSCodeHeuristic` use this default.
- **default-fingerprint-pattern**: The default `fingerprintPattern(for:)` MUST return `nil` when `extractPattern(from:)` returns `nil`, and otherwise MUST return the extracted pattern paired with `recommendedStrategy`; none of the five built-ins overrides it.
- **trim-spaces-and-tabs-only**: Every trim a heuristic performs MUST strip only horizontal whitespace (spaces and tabs, the `.whitespaces` set); newlines inside a title are preserved.
- **pattern-case-preserved**: A heuristic MUST return the extracted text with its original letter case; case folding is left to the matcher.

### Title separator parsing (`HeuristicTitleParser`)

- **separator-set**: `HeuristicTitleParser.separators` MUST be, in order, space + em dash (U+2014) + space, then space + en dash (U+2013) + space.
- **separator-first-match-wins**: `components(of:)` MUST split the title on every occurrence of the first separator in `separators` that the title contains, and MUST NOT additionally split on the other separator.
- **separator-components-trimmed**: `components(of:)` MUST trim spaces and tabs from each resulting component, keeping empty components in place.
- **separator-absent-single-component**: When the title contains neither separator, `components(of:)` MUST return a one-element array holding the trimmed title; it never returns an empty array.
- **separator-hyphen-not-split**: `components(of:)` MUST NOT treat an ASCII hyphen surrounded by spaces (" - ") as a separator.

### `XcodeHeuristic`

- **xcode-identity**: `XcodeHeuristic` MUST have `name` "Xcode" and `appNames` exactly `["Xcode"]`.
- **xcode-first-component**: `XcodeHeuristic` MUST return the first `HeuristicTitleParser` component of the title (the project name before the em or en dash).
- **xcode-no-separator-whole-title**: With no dash separator, `XcodeHeuristic` MUST return the whole trimmed title (for example an organizer window titled "MyApp").
- **xcode-empty-first-component-nil**: `XcodeHeuristic` MUST return `nil` when the first component is empty after trimming.

### `WarpHeuristic`

- **warp-identity**: `WarpHeuristic` MUST have `name` "Warp" and `appNames` exactly `["Warp"]`.
- **warp-requires-hyphen-separator**: `WarpHeuristic` MUST return `nil` when the title does not contain " - " (space, ASCII hyphen, space); unlike the other heuristics it has no whole-title fallback and does not use `HeuristicTitleParser`.
- **warp-remainder-after-first-separator**: `WarpHeuristic` MUST take everything after the first " - " occurrence, trimmed, as the remainder; later " - " occurrences stay inside the remainder.
- **warp-strip-dirty-indicator**: When the remainder ends with " *" (space, asterisk), `WarpHeuristic` MUST remove those two characters.
- **warp-strip-branch**: After the dirty indicator is handled, `WarpHeuristic` MUST cut the remainder at its first " (" (space, open parenthesis), discarding that and everything after it, then trim.
- **warp-path-last-component**: When the remaining text contains "/", `WarpHeuristic` MUST return its last non-empty "/"-separated component, trimmed.
- **warp-root-path-nil**: When the remaining text contains "/" but has no non-empty "/"-separated component (for example "/"), `WarpHeuristic` MUST return `nil`, not a literal slash.
- **warp-plain-remainder**: When the remaining text has no "/", `WarpHeuristic` MUST return it, or `nil` when it is empty.

### `BraveHeuristic`

- **brave-identity**: `BraveHeuristic` MUST have `name` "Brave Browser" and `appNames` exactly `["Brave Browser"]`.
- **brave-strip-suffix**: When the title ends with " - Brave", `BraveHeuristic` MUST return the text before that suffix, trimmed, or `nil` when that text is empty.
- **brave-bare-app-name-nil**: When the trimmed title equals "Brave" exactly, `BraveHeuristic` MUST return `nil`.
- **brave-fallback-whole-title**: Any other non-empty title MUST produce the whole trimmed title, or `nil` when trimming leaves it empty.
- **brave-suffix-case-sensitive**: The " - Brave" suffix and the bare "Brave" comparison MUST be case-sensitive exact matches; " - brave" and " - Brave Browser" do not strip.

### `VSCodeHeuristic`

- **vscode-identity**: `VSCodeHeuristic` MUST have `name` "VS Code" and `appNames` exactly `["Code", "Visual Studio Code", "Cursor"]`.
- **vscode-generic-titles**: `VSCodeHeuristic` MUST treat exactly "Visual Studio Code", "Welcome", "Get Started" and "Settings" as generic titles, compared case-sensitively.
- **vscode-single-component**: With no dash separator, `VSCodeHeuristic` MUST return `nil` when the trimmed title is a generic title, and otherwise MUST return the trimmed title (`nil` when empty).
- **vscode-generic-last-returns-first**: With two or more components, when the last component is a generic title, `VSCodeHeuristic` MUST return the first component (`nil` when empty), even when that first component is itself generic.
- **vscode-filename-first-prefers-last**: With two or more components, when the last component is not generic, the first looks like a filename and the last does not, `VSCodeHeuristic` MUST return the last component (`nil` when empty).
- **vscode-default-first**: In every other multi-component case, `VSCodeHeuristic` MUST return the first component (`nil` when empty).
- **vscode-filename-test**: A string MUST count as a filename when splitting it on "." (dropping empty pieces) yields at least two pieces and the last piece, lowercased, is one of: swift, ts, tsx, js, jsx, go, py, rs, rb, java, kt, c, cpp, h, hpp, cs, json, yaml, yml, toml, md, txt, html, css, scss, vue, svelte.
- **vscode-welcome-doc-contract**: NEEDS REVIEW: Not implemented in source. The `VSCodeHeuristic` doc comment declares "Welcome — Visual Studio Code" -> nil ("not a project window"), but `extractPattern(from:)` returns "Welcome" for that title because the generic-last branch returns the first component without checking it against the generic set; deciding whether the code or the doc comment is authoritative (and adding a test for this title to `HeuristicTests`) settles it.

### `TerminalHeuristic`

- **terminal-identity**: `TerminalHeuristic` MUST have `name` "Terminal" and `appNames` exactly `["Terminal"]`.
- **terminal-strategy-app-only**: `TerminalHeuristic.recommendedStrategy` MUST be `MatchStrategy.appOnly` for every title, because plain shell titles are not distinctive; its fingerprints therefore store the extracted pattern with the app-only strategy.
- **terminal-second-component**: With two or more `HeuristicTitleParser` components, `TerminalHeuristic` MUST return the second component (the process or command).
- **terminal-strip-one-dash**: When that second component starts with "-", `TerminalHeuristic` MUST drop exactly one leading "-" (the login-shell marker, "-zsh" to "zsh"), and MUST return `nil` when nothing remains.
- **terminal-empty-second-nil**: `TerminalHeuristic` MUST return `nil` when the second component is empty.
- **terminal-single-component**: With no dash separator, `TerminalHeuristic` MUST return the whole trimmed title, or `nil` when it is empty.

