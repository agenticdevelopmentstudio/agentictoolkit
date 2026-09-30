<!-- leaf: implement-window/matching · source: window-matching.md -->

**Rules** (cite as `implement-window/matching#<slug>`):

- `heuristic-name` MUST
- `heuristic-app-names` MUST
- `heuristic-extract-pattern` MUST
- `heuristic-default-strategy` MUST
- `heuristic-default-fingerprint-pattern` MUST
- `heuristic-sendable` MUST
- `parser-separators` MUST
- `parser-first-separator-wins` MUST
- `parser-trim` MUST
- `parser-no-separator` MUST
- `parser-en-dash-split` MUST
- `match-mode-cases` MUST
- `match-mode-display-name` MUST
- `rule-fields` MUST
- `rule-init-defaults` MUST
- `rule-default-name` MUST
- `rule-value-semantics` MUST
- `rule-empty-pattern` MUST
- `rule-substring-match` MUST
- `rule-regex-match` MUST
- `rule-regex-non-empty` MUST
- `rule-regex-invalid` MUST
- `rule-regex-unmappable-range` MUST
- `rule-app-name-case` MUST
- `rule-auto-assign` MUST
- `custom-name` MUST
- `custom-app-names` MUST
- `custom-extract` MUST
- `custom-strategy` MUST
- `custom-fingerprint-unmatched` MUST
- `custom-fingerprint-substring` MUST
- `custom-fingerprint-regex` MUST
- `store-root` MUST
- `store-file-path` MUST
- `store-load-missing` MUST
- `store-load-decode` MUST
- `store-load-errors` MUST
- `store-save-directory` MUST
- `store-save-format` MUST
- `store-save-atomic` MUST
- `store-remove-all` MUST
- `store-isolation` MUST
- `store-no-cache` MUST

# Window Matching

## Overview

Window Matching is the logic layer that lets a window-context system recognise
"the same window" across app restarts and reboots, when the CGWindowID has
changed. It lives in `AgenticToolkit/Core/SystemWindows/Matching/` and consists
of:

- `AppHeuristic` — a protocol for per-app title parsers that pull a stable
  identifying pattern (project name, page title, process) out of a window
  title, plus `HeuristicTitleParser`, the shared separator splitter.
- `CustomMatchMode` and `CustomHeuristicRule` — a user-defined rule (app name +
  substring or regex title pattern) — and `CustomHeuristic`, which adapts a rule
  to `AppHeuristic`.
- `CustomHeuristicStore` — persists rules to `heuristics.json` in a
  caller-supplied directory.
- `HeuristicRegistry` — a thread-safe, case-insensitive app-name → heuristic
  lookup pre-populated with the five built-ins, where custom rules override
  built-ins for the same app.
- `SystemWindowMatcher` — creates a `SystemWindowFingerprint` from a live
  `SystemWindowInfo`, scores a live window against a fingerprint, and runs a
  greedy one-to-one assignment of dormant `SystemWindowSnapshot`s (in
  `SystemWindowContext`s) to live windows.

Use it whenever a window must be persisted by identity rather than by a
volatile OS handle. The data types it consumes (`MatchStrategy`,
`SystemWindowFingerprint`, `SystemWindowInfo`, `SystemWindowSnapshot`,
`SystemWindowContext`) live one directory up in `Core/SystemWindows/` and are
specified in Window Matching Core System Windows.
The per-app built-in parsers (`XcodeHeuristic`, `WarpHeuristic`,
`BraveHeuristic`, `VSCodeHeuristic`, `TerminalHeuristic`) live in
`Matching/Heuristics/` and are specified in
Window Matching Heuristics;
this recipe specifies only their registration, not their parsing rules.

## Behavioral Requirements

### AppHeuristic contract

- **heuristic-name**: An `AppHeuristic` MUST expose `name`, a user-visible string (for example "Xcode").
- **heuristic-app-names**: An `AppHeuristic` MUST expose `appNames`, the owning-application names it applies to, compared against the window owner name reported by the window server (for example "Xcode", "Brave Browser", "Code").
- **heuristic-extract-pattern**: `extractPattern(from:)` MUST return the stable identifying portion of a raw title, or nil when the title does not match the heuristic's expected format.
- **heuristic-default-strategy**: When a heuristic does not override `recommendedStrategy`, it MUST be `.appAndTitleSubstring`.
- **heuristic-default-fingerprint-pattern**: When a heuristic does not override `fingerprintPattern(for:)`, it MUST return `(extractPattern(from: title), recommendedStrategy)`, or nil when `extractPattern` returns nil.
- **heuristic-sendable**: `AppHeuristic` MUST be `Sendable`, so a heuristic value can be shared across isolation domains.

### HeuristicTitleParser

- **parser-separators**: `HeuristicTitleParser.separators` MUST be, in order, space + em dash (U+2014) + space, then space + en dash (U+2013) + space.
- **parser-first-separator-wins**: `components(of:)` MUST split on the first separator in `separators` order that the title contains, and only on that separator.
- **parser-trim**: Each returned component MUST be trimmed of leading and trailing spaces and tabs (whitespace, not newlines).
- **parser-no-separator**: When the title contains no separator, `components(of:)` MUST return a single element: the trimmed title.
- **parser-en-dash-split**: A title whose content contains " – " (en dash with spaces) MUST be split there when it contains no em-dash separator; this trade-off is intentional per the source's NOTE.

### CustomMatchMode and CustomHeuristicRule

- **match-mode-cases**: `CustomMatchMode` MUST have exactly two cases, `substring` and `regex`, encoded as the raw strings `"substring"` and `"regex"`.
- **match-mode-display-name**: `CustomMatchMode.displayName` MUST return "Substring" for `.substring` and "Regex" for `.regex`.
- **rule-fields**: `CustomHeuristicRule` MUST carry `id` (UUID, immutable), `appName`, `titlePattern`, `matchMode`, `autoAssign`, `targetContextName` (optional), `name`, and `createdAt` (Date, immutable).
- **rule-init-defaults**: The initializer MUST default `id` to a new UUID, `matchMode` to `.substring`, `autoAssign` to false, `targetContextName` to nil, `name` to empty, and `createdAt` to the current date.
- **rule-default-name**: When `name` is empty at initialization, the rule's `name` MUST become `"<appName> - <titlePattern>"`.
- **rule-value-semantics**: `CustomHeuristicRule` MUST be `Codable`, `Equatable`, `Identifiable` and `Sendable`.
- **rule-empty-pattern**: `matchTitle(_:)` MUST return nil for every title when `titlePattern` is empty.
- **rule-substring-match**: In `.substring` mode, `matchTitle(_:)` MUST return `titlePattern` itself (not the title's matching slice) when the title contains it under a locale-aware case-insensitive comparison, and nil otherwise.
- **rule-regex-match**: In `.regex` mode, `matchTitle(_:)` MUST compile `titlePattern` as a case-insensitive regular expression and return the text of the first match in the title.
- **rule-regex-non-empty**: In `.regex` mode, a zero-length first match (for example from `.*` on an empty title, `^`, or a word-boundary pattern) MUST yield nil.
- **rule-regex-invalid**: In `.regex` mode, an uncompilable pattern MUST yield nil and MUST log one error-level message on the `CustomHeuristicRule` logger containing the pattern and the compiler's reason, on every call.
- **rule-regex-unmappable-range**: In `.regex` mode, a match whose range cannot be mapped back onto the title's characters MUST yield nil rather than trap.
- **rule-app-name-case**: The rule's `appName` MUST be matched case-insensitively against the window owner name (enforced by the registry's lowercased key, see registry-case-insensitive).
- **rule-auto-assign**: `autoAssign` and `targetContextName` are consumed outside this package, by `SystemWindowContextManager.checkCustomRulesForAutoAssignment(_:)` (called from `SystemWindowContextsModel`): for a window not already in any context, it walks its own `customHeuristicRules` list in order and, for the first rule with `autoAssign` true, a case-insensitive `appName` match, a title match and a `targetContextName` that names an existing context (case-insensitively), adds the window to that context. A rule whose target context does not exist is skipped. This recipe's types only carry the fields; a port MUST keep them so that consumer can read them.

### CustomHeuristic

- **custom-name**: `CustomHeuristic.name` MUST equal `rule.name`.
- **custom-app-names**: `CustomHeuristic.appNames` MUST be the one-element array `[rule.appName]`.
- **custom-extract**: `CustomHeuristic.extractPattern(from:)` MUST return `rule.matchTitle(title)`.
- **custom-strategy**: `CustomHeuristic.recommendedStrategy` MUST be `.appAndTitleRegex` for a regex rule and `.appAndTitleSubstring` for a substring rule.
- **custom-fingerprint-unmatched**: `CustomHeuristic.fingerprintPattern(for:)` MUST return nil when the rule does not match the title.
- **custom-fingerprint-substring**: For a matching title and a substring rule, `fingerprintPattern(for:)` MUST return `(rule.titlePattern, .appAndTitleSubstring)`.
- **custom-fingerprint-regex**: For a matching title and a regex rule, `fingerprintPattern(for:)` MUST return the regex source `(rule.titlePattern, .appAndTitleRegex)`, never the captured text, so sibling titles ("JIRA-1234", "JIRA-9999") re-match the same fingerprint.

### CustomHeuristicStore

- **store-root**: `CustomHeuristicStore` MUST store rules in a caller-supplied `rootDirectory`; it MUST NOT choose an application-specific location itself.
- **store-file-path**: `heuristicsFilePath` MUST be `rootDirectory/heuristics.json`.
- **store-load-missing**: `loadRules()` MUST return an empty array when `heuristics.json` does not exist.
- **store-load-decode**: `loadRules()` MUST decode the file as a JSON array of `CustomHeuristicRule` with ISO 8601 dates.
- **store-load-errors**: `loadRules()` MUST throw the underlying read or decoding error unchanged when the file exists but cannot be read or decoded; it MUST NOT fall back to an empty array in that case.
- **store-save-directory**: `saveRules(_:)` MUST create `rootDirectory`, including intermediate directories, when it does not exist.
- **store-save-format**: `saveRules(_:)` MUST encode the full rule array as pretty-printed JSON with sorted keys and ISO 8601 dates.
- **store-save-atomic**: `saveRules(_:)` MUST write the file atomically, replacing the previous contents in full; it MUST throw any directory-creation, encoding or write error.
- **store-remove-all**: `removeAll()` MUST delete `heuristics.json` when it exists, MUST do nothing when it does not, and MUST NOT delete `rootDirectory`.
- **store-isolation**: `CustomHeuristicStore` is a `public final class` with no `Sendable` conformance; it MUST be used from one isolation domain, and its operations are synchronous blocking file I/O.
- **store-no-cache**: The store MUST NOT cache rules in memory; each `loadRules()` reads the file.

