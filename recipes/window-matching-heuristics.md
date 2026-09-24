---
id: 77dbd38e-9acd-4053-ba54-738b45101f6b
title: Window Matching Heuristics
domain: agentictoolkit://recipes/window-matching-heuristics
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Built-in per-app window-title parsers (Xcode, Warp, Brave, VS Code, Terminal)
  that extract a stable identifying pattern for window fingerprints.
platforms:
- swift
- macos
tags:
- system-windows
- window-matching
- heuristics
- macos
- foundation
- sendable
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/Core/SystemWindows/Matching/Heuristics/XcodeHeuristic.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SystemWindows/Matching/Heuristics/WarpHeuristic.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SystemWindows/Matching/Heuristics/BraveHeuristic.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SystemWindows/Matching/Heuristics/VSCodeHeuristic.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SystemWindows/Matching/Heuristics/TerminalHeuristic.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SystemWindows/Matching/AppHeuristic.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SystemWindows/MatchStrategy.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SystemWindows/Matching/HeuristicRegistry.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/SystemWindows/HeuristicTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a set of pure window-title parsing functions, not a visual component.

## States

Not applicable — this is a set of pure window-title parsing functions, not a visual component.

## Accessibility

Not applicable — this is a set of pure window-title parsing functions, not a visual component.

## Conformance Test Vectors

Titles below write the em dash as "—" (U+2014) and the en dash as "–"
(U+2013). Vectors marked (test) are asserted in `HeuristicTests.swift`; the
rest are traced to the heuristic's code and doc-comment examples.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wmh-001 | xcode-first-component | `XcodeHeuristic().extractPattern(from: "MyApp — ContentView.swift")` (test) | "MyApp" |
| wmh-002 | separator-set, xcode-first-component | `XcodeHeuristic().extractPattern(from: "MyApp – ContentView.swift")` (test) | "MyApp" |
| wmh-003 | xcode-no-separator-whole-title | `XcodeHeuristic().extractPattern(from: "MyApp")` | "MyApp" |
| wmh-004 | xcode-first-component | "QualityTime — ContentView.swift (Edited)" | "QualityTime" |
| wmh-005 | xcode-empty-first-component-nil | "   " (three spaces) | `nil` |
| wmh-006 | empty-title-nil | "" passed to each of the five heuristics | `nil` from all five |
| wmh-007 | separator-hyphen-not-split, xcode-no-separator-whole-title | Xcode, "MyApp - ContentView.swift" | "MyApp - ContentView.swift" |
| wmh-008 | separator-first-match-wins | `HeuristicTitleParser.components(of: "A — B – C")` | `["A", "B – C"]` |
| wmh-009 | separator-absent-single-component | `HeuristicTitleParser.components(of: "  zsh ")` | `["zsh"]` |
| wmh-010 | separator-components-trimmed | `HeuristicTitleParser.components(of: "a — ")` | `["a", ""]` |
| wmh-011 | warp-path-last-component, warp-strip-branch | `WarpHeuristic().extractPattern(from: "mike - ~/projects/myapp (develop)")` (test) | "myapp" |
| wmh-012 | warp-root-path-nil | `WarpHeuristic().extractPattern(from: "user - / (main)")` (test) | `nil` |
| wmh-013 | warp-strip-dirty-indicator, warp-strip-branch | "Claude - QualityTime (main) *" | "QualityTime" |
| wmh-014 | warp-plain-remainder | "mike - Documents" | "Documents" |
| wmh-015 | warp-requires-hyphen-separator | "QualityTime — main" | `nil` |
| wmh-016 | warp-remainder-after-first-separator | "a - b - c" | "b - c" |
| wmh-017 | warp-path-last-component | "mike - ~/projects/myapp/" | "myapp" |
| wmh-018 | brave-strip-suffix | "GitHub - Pull Requests - Brave" | "GitHub - Pull Requests" |
| wmh-019 | brave-bare-app-name-nil | "Brave" | `nil` |
| wmh-020 | brave-strip-suffix | " - Brave" | `nil` |
| wmh-021 | brave-fallback-whole-title, brave-suffix-case-sensitive | "Docs - Brave Browser" | "Docs - Brave Browser" |
| wmh-022 | vscode-default-first | `VSCodeHeuristic().extractPattern(from: "temporal — api.go")` (test) | "temporal" |
| wmh-023 | vscode-filename-first-prefers-last, vscode-filename-test | "settings.json — myproject" | "myproject" |
| wmh-024 | vscode-default-first | "api.go — main.ts" | "api.go" |
| wmh-025 | vscode-single-component, vscode-generic-titles | "Welcome" | `nil` |
| wmh-026 | vscode-generic-last-returns-first | "Welcome — Visual Studio Code" | "Welcome" (the doc comment says `nil`; see the open question on vscode-welcome-doc-contract) |
| wmh-027 | vscode-default-first | " — foo" (leading space, empty first component) | `nil` |
| wmh-028 | vscode-filename-test | "notes.JSON — proj" | "proj" (extension match is case-insensitive) |
| wmh-029 | terminal-second-component, terminal-strip-one-dash | "mfullerton — -zsh — 80x24" | "zsh" |
| wmh-030 | terminal-second-component | "mfullerton — ssh user@host" | "ssh user@host" |
| wmh-031 | terminal-strip-one-dash | "u — --x" | "-x" |
| wmh-032 | terminal-strip-one-dash | "u — -" | `nil` |
| wmh-033 | terminal-single-component | "bash" | "bash" |
| wmh-034 | terminal-strategy-app-only, default-fingerprint-pattern | `TerminalHeuristic().fingerprintPattern(for: "u — vim — 80x24")` | `(pattern: "vim", strategy: .appOnly)` |
| wmh-035 | default-strategy-substring, default-fingerprint-pattern | `XcodeHeuristic().fingerprintPattern(for: "MyApp — a.swift")` | `(pattern: "MyApp", strategy: .appAndTitleSubstring)` |
| wmh-036 | default-fingerprint-pattern | `BraveHeuristic().fingerprintPattern(for: "Brave")` | `nil` |
| wmh-037 | xcode-identity, warp-identity, brave-identity, vscode-identity, terminal-identity | read `name` and `appNames` of each built-in | "Xcode"/`["Xcode"]`; "Warp"/`["Warp"]`; "Brave Browser"/`["Brave Browser"]`; "VS Code"/`["Code", "Visual Studio Code", "Cursor"]`; "Terminal"/`["Terminal"]` |
| wmh-038 | heuristic-pure, heuristic-sendable | call `extractPattern(from:)` on one shared instance from many concurrent tasks with the same title | every call returns the same value; no data race is reported under strict concurrency checking |

## Edge Cases

- **Empty title**: every built-in returns `nil` for "" before doing any parsing (MUST; `empty-title-nil`).
- **Whitespace-only title**: Xcode, Brave, VS Code and Terminal trim to empty and return `nil`; Warp returns `nil` because there is no " - " (MUST).
- **Title with newlines**: trimming uses spaces and tabs only, so a leading or trailing newline stays in the returned pattern (MUST; `trim-spaces-and-tabs-only`).
- **Both em and en dash present**: only the em dash splits; en-dash text stays inside a component (MUST; `separator-first-match-wins`).
- **En dash inside content**: a title whose content contains " – " (for example a folder named "App – Prod") with no em dash is split there; `HeuristicTitleParser`'s NOTE records this as an accepted trade-off (MUST, as documented behavior).
- **Empty components from a leading or trailing separator**: components are kept in place, empty; Xcode, VS Code and Terminal return `nil` when the component they select is empty rather than falling back to another component (MUST).
- **Warp title with no " - "**: returns `nil`, with no whole-title fallback (MUST; `warp-requires-hyphen-separator`).
- **Warp root or slash-only path**: "/" or "//" yields `nil` (MUST; `warp-root-path-nil`).
- **Warp dirty indicator without a leading space**: "a - proj*" keeps the "*" ("proj*"), because only the two-character " *" suffix is stripped (MUST).
- **Warp parenthesis without a leading space**: "a - proj(main)" keeps "proj(main)", because only " (" cuts the branch (MUST).
- **Brave suffix variants**: " - brave" (lowercase) or " - Brave Browser" do not strip; the whole trimmed title is returned (MUST; `brave-suffix-case-sensitive`).
- **VS Code generic title in the first position**: "Welcome — Visual Studio Code" returns "Welcome" (MUST, as the code behaves); the doc comment claims `nil` — the open question on vscode-welcome-doc-contract.
- **VS Code generic comparison case**: "welcome" (lowercase) is not generic and is returned as-is (MUST).
- **VS Code dotted names that are not filenames**: "v1.2 — proj" returns "v1.2" because "2" is not a listed extension; ".json" alone is one piece after dropping the empty prefix and does not count as a filename (MUST; `vscode-filename-test`).
- **VS Code both first and last look like filenames**: the first component is returned (MUST; `vscode-default-first`).
- **Terminal double dash**: only one leading "-" is removed (MUST; `terminal-strip-one-dash`).
- **Terminal dimensions only**: "u — 80x24" returns "80x24" as the command, since the second component is taken blindly (MUST).
- **App-name lookup**: which heuristic runs for a window is decided by `HeuristicRegistry` (case-insensitive match against `appNames`); an app that no heuristic lists gets no heuristic and the matcher uses the raw title. This lookup belongs to the registry, not to the heuristics (fact).
- **Null input**: not applicable — `title` is a non-optional `String`, so there is no null case.
- **Concurrent access**: all five heuristics are stateless `Sendable` structs with pure functions; concurrent calls cannot interleave on shared state (MUST; `heuristic-pure`).
- **Error states, cancellation, timeouts, offline**: not applicable — the heuristics perform no I/O, cannot fail except by returning `nil`, run synchronously in time linear in the title length, and have nothing to cancel or time out.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` (argument to `extractPattern(from:)` / `fingerprintPattern(for:)`) | `String` | — (required) | The raw window title supplied by the caller (the window list's title for the window). |
| `HeuristicTitleParser.separators` | `[String]` (static `let`) | `[" — ", " – "]` | Title separators, most specific first; a constant, not caller-configurable. |
| `recommendedStrategy` | `MatchStrategy` | `.appAndTitleSubstring` (`TerminalHeuristic`: `.appOnly`) | Strategy stored in fingerprints produced by each heuristic; fixed per type. |
| `appNames` | `[String]` | per heuristic (see identity requirements) | Owning-app names the registry maps to the heuristic; fixed per type. |

The heuristics take no initializer parameters (`init()` only), read no
environment variables or settings keys, and have no injected dependencies.

## Deep Linking

Not applicable: the heuristics are pure title-parsing functions with no screen or route to link to.

## Localization

The heuristics produce no user-facing messages. Each `name` is a hardcoded
English (or product-name) literal documented as "the user-visible name for
this heuristic", with no localization lookup:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (literal, `XcodeHeuristic.name`) | Xcode | Heuristic display name |
| (literal, `WarpHeuristic.name`) | Warp | Heuristic display name |
| (literal, `BraveHeuristic.name`) | Brave Browser | Heuristic display name |
| (literal, `VSCodeHeuristic.name`) | VS Code | Heuristic display name |
| (literal, `TerminalHeuristic.name`) | Terminal | Heuristic display name |

The parsing literals (" - Brave", the VS Code generic titles "Visual Studio
Code", "Welcome", "Get Started", "Settings") match English application
titles only; a localized VS Code or Brave title is not recognized and falls
through to the default branch.

## Accessibility Options

Not applicable: the heuristics have no visual output, so Reduce Motion, Increase Contrast and Differentiate Without Color have nothing to act on.

## Feature Flags

Not applicable: no heuristic reads a flag; all five are always registered by `HeuristicRegistry.builtInHeuristics`.

## Analytics

Not applicable: the heuristics emit no events and call no analytics service.

## Privacy

Not applicable: the heuristics read a window title only in memory and return a substring of it, storing and transmitting nothing (persisting fingerprints is the caller's concern).

## Logging

Not applicable: none of the five heuristics nor `HeuristicTitleParser` logs anything; a failed extraction is signalled only by the `nil` return.

## Platform Notes

- **SwiftUI**: Source platform (the logic is Foundation-only and has no SwiftUI dependency). Files: `Core/SystemWindows/Matching/AppHeuristic.swift` (protocol, default `recommendedStrategy`/`fingerprintPattern(for:)`, `HeuristicTitleParser`), `Matching/Heuristics/XcodeHeuristic.swift`, `WarpHeuristic.swift`, `BraveHeuristic.swift`, `VSCodeHeuristic.swift`, `TerminalHeuristic.swift`, and `Core/SystemWindows/MatchStrategy.swift`. Swift specifics a port must reproduce: `String.components(separatedBy:)` keeps empty pieces while `split(separator:)` drops them (VS Code's filename test and Warp's path split rely on the dropping form); `trimmingCharacters(in: .whitespaces)` excludes newlines; `hasSuffix`/`range(of:)` are literal, case-sensitive matches; `dropLast(n)` counts `Character`s. A SwiftUI host would show `name` in a picker and read `MatchStrategy.displayName` for the strategy label.
- **Compose**: Port to plain Kotlin — an `interface AppHeuristic` with default methods for `recommendedStrategy` and `fingerprintPattern`, `object`/`data object` implementations, and a `Pair<String, MatchStrategy>?` (or small data class) for the fingerprint result. Use `String.split(" — ")` (keeps empty pieces, like `components(separatedBy:)`) for the separator, and `split('.').filter { it.isNotEmpty() }` for the filename test. Kotlin's `trim()` strips all whitespace including newlines; use `trim { it == ' ' || it == '\t' }` to match `.whitespaces`. `endsWith`/`startsWith` are case-sensitive by default, matching the source. Stateless objects are thread-safe, matching `Sendable`.
- **React/Web**: Port to TypeScript — an `AppHeuristic` interface plus a helper providing the default strategy (`'appAndTitleSubstring'`) and fingerprint derivation, returning `string | null` / `{ pattern, strategy } | null`. `String.prototype.split(' — ')` keeps empty pieces; filter empties for the filename and Warp path cases. `trim()` also strips newlines, so use a replace against a space/tab-only class to match `.whitespaces`. `endsWith`/`indexOf(' (')` reproduce `hasSuffix`/`range(of:)`. JS strings index UTF-16 code units, while Swift `dropLast` counts grapheme clusters; the suffixes involved (" - Brave", " *", "-") are ASCII, so results are identical.
- **AppKit / UIKit**: Same as the source; the heuristics are Foundation-only and run unchanged in an AppKit or UIKit host. On macOS the `title` comes from the window list's window name and `appNames` are compared with the owning-app name (`CGWindowListCopyWindowInfo`'s owner name, per the `AppHeuristic` doc comment); UIKit has no equivalent system-wide window list, so on iOS the heuristics apply only to titles supplied by the app itself.
- **WinUI 3**: Port to C# in a .NET class library — `public interface IAppHeuristic` with C# 8 default interface members for `RecommendedStrategy` (returning `MatchStrategy.AppAndTitleSubstring`) and `FingerprintPattern(string title)` returning `(string Pattern, MatchStrategy Strategy)?`; implement each heuristic as a `sealed record` or stateless `sealed class` (immutable, therefore thread-safe like `Sendable`, and callable from any `Task`). Use `title.Split(" — ", StringSplitOptions.None)` to keep empty components like `components(separatedBy:)`, and `Split('.', StringSplitOptions.RemoveEmptyEntries)` for the filename test and Warp's path split. `string.Trim()` strips all whitespace including newlines; use `Trim(' ', '\t')` to match `.whitespaces`. Use `EndsWith(" - Brave", StringComparison.Ordinal)`, `StartsWith("-", StringComparison.Ordinal)`, and `IndexOf(" (", StringComparison.Ordinal)` — the default culture-sensitive overloads differ from Swift's literal matching; a `HashSet<string>` with `StringComparer.Ordinal` holds the generic titles, and `StringComparer.OrdinalIgnoreCase` (or `ToLowerInvariant()`) holds the extension set. The title formats themselves are macOS-specific: on Windows the window title comes from `GetWindowText` (Win32) or the Windows App SDK `AppWindow.Title`, the owner is a process name such as "Code.exe" or "WindowsTerminal.exe", and title shapes differ (VS Code on Windows uses " - " rather than an em dash, Brave appends " - Brave" the same way), so `AppNames` and separators need Windows-specific values while the parsing rules port unchanged. `MatchStrategy` maps to a C# `enum` serialized by name with `System.Text.Json`'s `JsonStringEnumConverter` to keep the source's `String` raw values.

## Design Decisions

**Decision**: A heuristic returns `nil` rather than an empty string or an error when it cannot extract a pattern.
**Rationale**: `SystemWindowMatcher` treats `nil` as "fall back to the raw title with the substring strategy" (or app-only for an empty title); a single optional result keeps the heuristics pure and leaves the fallback policy in one place.
**Approved**: pending

**Decision**: `HeuristicTitleParser` splits on the en dash as well as the em dash, accepting that content containing " – " gets split.
**Rationale**: The parser's NOTE states em dash is by far the common separator, a few locales/builds use an en dash, and content en-dashes are rare; the behavior is covered by `HeuristicTests` (the Xcode en-dash test).
**Approved**: pending

**Decision**: `TerminalHeuristic` recommends `appOnly` for every title, not only for plain shells.
**Rationale**: The doc comment states plain-shell titles are not distinctive enough and appOnly "is the safest default"; the code applies it unconditionally, so even a distinctive command such as "ssh user@host" is fingerprinted app-only while the extracted command is still stored as the pattern.
**Approved**: pending

**Decision**: `WarpHeuristic` returns `nil` for a root path instead of "/".
**Rationale**: The code comment and the `warpRoot` test state a bare root yields no useful pattern; returning "/" would substring-match every path-bearing Warp title.
**Approved**: pending

**Decision**: `VSCodeHeuristic` prefers the last component only when the first looks like a filename and the last does not, using a fixed list of 27 common extensions.
**Rationale**: VS Code puts the workspace first when one is open but shows "file — workspace" in other layouts; the fixed list avoids treating dotted project names (for example "v1.2") as filenames.
**Approved**: pending

**Decision**: Only `WarpHeuristic` parses an ASCII " - " and has no whole-title fallback; Brave parses the " - Brave" suffix; the rest use `HeuristicTitleParser`.
**Rationale**: Warp and Brave titles use a hyphen, not a dash separator; Warp without " - " is not in its "user - directory" format, so the heuristic declines rather than guessing.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

unit-test-coverage is partial: `HeuristicTests.swift` asserts Xcode (em and
en dash), one VS Code title, and two Warp titles, but has no test for
`BraveHeuristic` or `TerminalHeuristic`, none for the VS Code generic-title
and filename branches, and none for the "Welcome — Visual Studio Code" title
whose code result contradicts its doc comment. separation-of-concerns passes
because each app's title format lives in its own type, the separator logic is
centralized in `HeuristicTitleParser`, and app-name lookup and scoring stay in
`HeuristicRegistry` and `SystemWindowMatcher`. explicit-error-handling passes
because the only failure mode — no extractable pattern — is expressed in the
return type as `nil`, and the caller handles it explicitly with a documented
fallback. no-hardcoded-strings fails because each heuristic's user-visible
`name` is an English literal with no localization lookup, and the Brave and
VS Code parsing literals only recognize English application titles (see
Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from the five built-in title heuristics, `AppHeuristic` and `HeuristicTitleParser` |
