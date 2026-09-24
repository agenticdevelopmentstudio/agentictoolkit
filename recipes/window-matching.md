---
id: 840dc813-b4a3-483c-be87-2959ac551ea7
title: Window Matching
domain: agentictoolkit://recipes/window-matching
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: App title heuristics, user rules and their JSON store, window fingerprinting,
  scoring, and greedy one-to-one re-matching of dormant snapshots.
platforms:
- swift
- macos
tags:
- system-windows
- window-matching
- heuristics
- fingerprinting
- persistence
depends-on:
- agentictoolkit://recipes/window-matching-core-system-windows
related:
- agentictoolkit://recipes/window-matching-heuristics
- agentictoolkit://recipes/window-matching-core-mac-os-system-windows
references:
- https://developer.apple.com/documentation/foundation/nsregularexpression
- https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo
approved-by: ''
approved-date: ''
---

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
specified in [Window Matching Core System Windows](agentictoolkit://recipes/window-matching-core-system-windows).
The per-app built-in parsers (`XcodeHeuristic`, `WarpHeuristic`,
`BraveHeuristic`, `VSCodeHeuristic`, `TerminalHeuristic`) live in
`Matching/Heuristics/` and are specified in
[Window Matching Heuristics](agentictoolkit://recipes/window-matching-heuristics);
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

### HeuristicRegistry

- **registry-built-ins**: `HeuristicRegistry.builtInHeuristics` MUST be, in order, `XcodeHeuristic`, `WarpHeuristic`, `BraveHeuristic`, `VSCodeHeuristic`, `TerminalHeuristic`, covering the app names "Xcode", "Warp", "Brave Browser", "Code", "Visual Studio Code", "Cursor" and "Terminal".
- **registry-shared**: `HeuristicRegistry.shared` MUST be a process-wide instance initialized with the built-ins.
- **registry-init**: `init(heuristics:)` MUST register the given heuristics, or the built-ins when the argument is nil, in array order.
- **registry-case-insensitive**: `heuristic(for:)` MUST look up the app name case-insensitively and return nil when no heuristic is registered for it.
- **registry-last-wins**: When two registered heuristics claim the same app name, the one registered later MUST be returned by `heuristic(for:)`.
- **registry-register**: `register(_:)` MUST append the heuristic to `heuristics` and map each of its app names, overwriting any earlier mapping for that name.
- **registry-custom-replace**: `registerCustomRules(_:)` MUST remove every previously registered `CustomHeuristic`, rebuild the lookup from the remaining heuristics, store the new rules as `customRules`, and then register one `CustomHeuristic` per rule in array order.
- **registry-custom-overrides**: After `registerCustomRules(_:)`, a custom rule for an app name MUST take precedence over a built-in or `register(_:)`-added heuristic for the same name.
- **registry-custom-clear**: `registerCustomRules([])` MUST restore the lookup to the non-custom heuristics and leave `customRules` empty.
- **duplicate-app-rules**: Custom rules are last-wins per app name. When two custom rules target the same app name, only the later one is returned by `heuristic(for:)` and so used for fingerprinting and scoring; the earlier rule stays in `customRules` (and in the Settings list) but is not consulted by the registry, and neither the rule type, the store nor the registry rejects or reports the duplicate.
- **registry-is-built-in**: `isBuiltIn(appName:)` MUST return false when any registered custom rule targets that app name (case-insensitive); otherwise it MUST return true exactly when a heuristic in the static `builtInHeuristics` list claims the name, regardless of which heuristics this instance was initialized with.
- **registry-snapshots**: The `heuristics` and `customRules` properties MUST return copies taken under the lock, in registration order.
- **registry-thread-safety**: Every read and write of the registry's mutable state MUST be serialized by one lock, so any single call is atomic and the registry is safe to share across threads (`@unchecked Sendable`).
- **registry-no-cross-call-snapshot**: The registry MUST NOT be assumed consistent across separate calls: `SystemWindowMatcher` performs one lookup per `fingerprint` or `score` call, so a caller that mutates custom rules concurrently with a `matchWindows` run can score different pairs against different rule sets. In the toolkit, `SystemWindowContextManager` is `@MainActor` and is the only caller of `registerCustomRules`, which orders its writes against its own matching.

### SystemWindowMatcher — fingerprinting

- **matcher-registry**: `SystemWindowMatcher` MUST use the injected `registry`, defaulting to `HeuristicRegistry.shared`.
- **matcher-isolation**: `SystemWindowMatcher` is a `public struct` with no `Sendable` conformance and no mutable state; the compiler keeps each instance in its isolation domain, and every operation is synchronous and pure except for logging.
- **fingerprint-heuristic**: `fingerprint(window:)` MUST, when a heuristic is registered for `window.app` and its `fingerprintPattern(for: window.title)` is non-nil, return a fingerprint with that pattern and strategy.
- **fingerprint-fallback**: When no heuristic is registered or it returns nil, `fingerprint(window:)` MUST use the full `window.title` as `titlePattern` with `.appAndTitleSubstring`.
- **fingerprint-empty-title**: When falling back and `window.title` is empty, the strategy MUST be `.appOnly` (with an empty `titlePattern`).
- **fingerprint-app-display**: Every fingerprint MUST copy `window.app` into `app` unchanged (original case) and `window.display` into `display`.
- **fingerprint-never-exact**: `fingerprint(window:)` MUST NOT produce `.appAndTitleExact` unless a registered heuristic's `fingerprintPattern` returns it; no heuristic in the package does, so that strategy only arises from fingerprints constructed elsewhere.

### SystemWindowMatcher — scoring

- **score-app-gate**: `score(window:against:)` MUST return 0 when `window.app` and `fingerprint.app` differ after lowercasing.
- **score-live-pattern**: For the exact and substring strategies, the live pattern MUST be the registered heuristic's `extractPattern(from: window.title)` when non-nil, else the raw `window.title`.
- **score-exact**: Under `.appAndTitleExact`, the title component MUST be 80 when the lowercased live pattern equals the lowercased `titlePattern`, and the total score MUST be 0 otherwise.
- **score-substring-equal**: Under `.appAndTitleSubstring`, the title component MUST be 80 when the lowercased live pattern equals the lowercased `titlePattern`.
- **score-substring-contains**: Under `.appAndTitleSubstring`, when not equal, the title component MUST be 60 when the lowercased pattern is at least `minSubstringPatternLength` (2) characters and is contained in the lowercased live pattern or the lowercased raw title.
- **score-substring-direction**: Substring matching MUST test only "live contains stored pattern"; a stored pattern that contains the live token MUST NOT match.
- **score-substring-miss**: Under `.appAndTitleSubstring`, when neither equality nor containment holds, the total score MUST be 0.
- **score-regex**: Under `.appAndTitleRegex`, the title component MUST be 80 when `titlePattern`, compiled case-insensitively, has a first match of non-zero length in the raw `window.title`, and the total score MUST be 0 otherwise; the app's heuristic MUST NOT be consulted.
- **score-regex-invalid**: Under `.appAndTitleRegex`, an empty or uncompilable `titlePattern` MUST score 0; an uncompilable one MUST also log one error-level message on the `SystemWindowMatcher` logger with the pattern and reason, on every call.
- **score-app-only**: Under `.appOnly`, the title component MUST be 80 regardless of title.
- **score-display-bonus**: When the title component is non-zero, the score MUST add 10 when `window.display == fingerprint.display`.
- **score-range**: Every score MUST be one of 0, 60, 70, 80 or 90.

### SystemWindowMatcher — re-matching

- **match-constants**: `autoAssignThreshold` MUST be 80 and `minSubstringPatternLength` MUST be 2.
- **match-default-threshold**: `matchWindows(contexts:liveWindows:threshold:)` MUST default `threshold` to `autoAssignThreshold`.
- **match-dormant-only**: Only snapshots with `windowID == nil` MUST be candidates for re-matching.
- **match-exclude-assigned**: A live window whose `id` equals any snapshot's non-nil `windowID` (in any context) MUST be excluded from candidates and from `unassignedWindows`.
- **match-threshold-filter**: Only pairs scoring at least `threshold` MUST become candidates; lower-scoring pairs MUST NOT consume a snapshot or a window.
- **match-order**: Candidates MUST be ordered by score descending, then `contextID.uuidString` ascending, then `snapshotID.uuidString` ascending, then window `id` ascending, so equal inputs always yield equal results.
- **match-greedy**: Walking candidates in that order, a candidate MUST be accepted only when neither its snapshot ID nor its window ID has already been accepted.
- **match-unmatched**: `unmatchedSnapshots` MUST list every dormant snapshot not accepted, as `(contextID, snapshotID)`, in context order then snapshot order.
- **match-unassigned**: `unassignedWindows` MUST list every candidate window not accepted, in `liveWindows` order.
- **match-result-order**: `matched` MUST list accepted candidates in acceptance order.
- **match-substring-default**: With the default threshold of 80, a substring-containment match (60, or 70 with the display bonus) MUST NOT be auto-assigned.
- **candidate-match-shape**: `CandidateMatch` MUST carry `contextID`, `snapshotID`, `window` (`SystemWindowInfo`) and `score`, and be `Equatable` by all four.
- **match-result-equality**: `MatchResult` equality MUST compare `matched` and `unassignedWindows` element-wise and `unmatchedSnapshots` by count and element-wise `contextID` and `snapshotID`.
- **match-no-side-effects**: `matchWindows` MUST NOT mutate contexts, snapshots or the registry; applying the result is the caller's job (`SystemWindowContextManager`).

## Appearance

Not applicable — this is a window-identity matching engine and rule store, not a visual component.

## States

Not applicable — this is a window-identity matching engine and rule store, not a visual component.

## Accessibility

Not applicable — this is a window-identity matching engine and rule store, not a visual component.

## Conformance Test Vectors

Vectors 001 to 013 are derived from `SystemWindowMatcherTests` and `HeuristicTests`; the rest from the source. Windows use `display: 99` and fingerprints `display: 0` unless stated.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| window-matching-001 | score-app-gate | fingerprint (Xcode, "Proj", substring); window (Other, "Proj") | score 0 |
| window-matching-002 | score-app-only | fingerprint (Terminal, "", appOnly); window (Terminal, "anything") | score 80 |
| window-matching-003 | score-substring-contains, match-constants | fingerprint (TestApp, "a", substring); window (TestApp, "banana") | score 0 (pattern shorter than 2) |
| window-matching-004 | score-substring-contains | fingerprint (TestApp, "ban", substring); window (TestApp, "banana") | score 60 |
| window-matching-005 | score-regex | fingerprint (TestApp, regex source JIRA-backslash-d-plus, regex); windows "JIRA-1234 details" and "no ticket" | 80 and 0 |
| window-matching-006 | score-display-bonus | fingerprint (Terminal, "", appOnly, display 7); window (Terminal, "x", display 7) | score 90 |
| window-matching-007 | match-threshold-filter, match-unmatched, match-unassigned, match-default-threshold | one context with a dormant snapshot of fingerprint (TestApp, "ban", substring); live window id 5 "banana" | default threshold: matched empty, 1 unmatched snapshot, unassigned ids [5]; threshold 60: matched count 1 |
| window-matching-008 | match-order, match-greedy | contexts A (UUID ...0001) and B (...0002), each one dormant appOnly Terminal snapshot; windows 10 and 20 (Terminal) | two runs return equal results; matched count 2 |
| window-matching-009 | match-result-equality | two `MatchResult`s differing only in the unmatched snapshot's IDs | not equal; each equals itself |
| window-matching-010 | parser-separators, parser-first-separator-wins | `XcodeHeuristic().extractPattern` on "MyApp" + em dash + "ContentView.swift", then the en-dash variant | "MyApp" both times |
| window-matching-011 | custom-fingerprint-regex, custom-fingerprint-unmatched | regex rule (Jira, JIRA-backslash-d-plus); titles "JIRA-1234 — details" and "no ticket here" | pattern is the regex source, strategy `.appAndTitleRegex`; then nil |
| window-matching-012 | custom-fingerprint-substring | substring rule (Notes, "Daily"); title "Daily Standup" | ("Daily", `.appAndTitleSubstring`) |
| window-matching-013 | registry-is-built-in, registry-custom-overrides | default registry; then `registerCustomRules` with a rule for "Xcode" | `isBuiltIn("Xcode")` true, then false |
| window-matching-014 | rule-empty-pattern | substring rule with `titlePattern` "" ; title "anything" | `matchTitle` returns nil |
| window-matching-015 | rule-substring-match | substring rule "dash"; title "My DASHBOARD" | returns "dash" (the pattern, not "DASH") |
| window-matching-016 | rule-regex-non-empty | regex rule ".*"; title "" | nil |
| window-matching-017 | rule-regex-invalid | regex rule with pattern "(" ; title "x" | nil, one error logged |
| window-matching-018 | rule-default-name | `CustomHeuristicRule(appName: "Safari", titlePattern: "Docs")` | `name` is "Safari - Docs" |
| window-matching-019 | fingerprint-fallback | window (UnknownApp, "Report.pdf", display 3) | fingerprint (UnknownApp, "Report.pdf", `.appAndTitleSubstring`, 3) |
| window-matching-020 | fingerprint-empty-title | window (UnknownApp, "") | fingerprint strategy `.appOnly`, pattern "" |
| window-matching-021 | score-exact | fingerprint (UnknownApp, "report", appAndTitleExact); windows "REPORT" and "report 2" | 80 and 0 |
| window-matching-022 | score-substring-direction | fingerprint (UnknownApp, "project alpha", substring); window "alpha" | score 0 |
| window-matching-023 | score-regex-invalid | fingerprint (TestApp, "[", appAndTitleRegex); window "[" | score 0, one error logged |
| window-matching-024 | match-exclude-assigned, match-dormant-only | context with a live snapshot (windowID 7) and a dormant appOnly Terminal snapshot; live windows 7 and 8 (Terminal) | matched pairs the dormant snapshot with window 8; window 7 absent from `unassignedWindows` |
| window-matching-025 | registry-case-insensitive, registry-last-wins | registry with no heuristics; `register` H1 for "Foo" then H2 for "foo" | `heuristic(for: "FOO")` is H2; `heuristic(for: "Bar")` nil |
| window-matching-026 | registry-custom-clear | default registry; `registerCustomRules([rule for "Xcode"])` then `registerCustomRules([])` | `heuristic(for: "Xcode")` is `XcodeHeuristic`; `customRules` empty |
| window-matching-027 | store-load-missing | store on an empty temporary directory | `loadRules()` returns [] |
| window-matching-028 | store-save-directory, store-save-format, store-load-decode | store on a non-existent nested directory; save two rules; load | directory created; file is sorted-key pretty JSON; loaded rules equal saved rules |
| window-matching-029 | store-load-errors | `heuristics.json` containing "not json" | `loadRules()` throws a decoding error |
| window-matching-030 | store-remove-all | save rules, call `removeAll()` twice | file gone, directory remains, second call does not throw |
| window-matching-031 | match-substring-default | dormant substring snapshot (TestApp, "ban", display 1); window "banana" on display 1 | score 70; not matched at default threshold |
| window-matching-032 | parser-trim, parser-no-separator | `components(of: "  solo  ")` | ["solo"] |

## Edge Cases

- **Empty window title**: `fingerprint(window:)` MUST fall back to `.appOnly`, so any same-app window later scores at least 80 against it.
- **Empty stored pattern under substring**: a `.appAndTitleSubstring` fingerprint with `titlePattern` "" MUST score 80 only against a window whose live pattern is empty, and 0 otherwise (the 2-character minimum blocks containment).
- **Empty rule pattern**: `matchTitle` MUST return nil, so a `CustomHeuristic` with an empty pattern never fingerprints and the matcher falls back to the full title.
- **Empty app name on a rule**: the rule MUST be registered under the empty key and apply only to windows whose owner name is empty; nothing rejects it.
- **Invalid regex in a rule or fingerprint**: MUST yield no match and log an error; the regex is recompiled and the error re-logged on every call, with no caching.
- **Zero-width regex**: patterns that match the empty string MUST NOT count as matches, in both `CustomHeuristicRule.matchTitle` and matcher scoring.
- **Title content containing " – "**: MUST be split as if it were a separator when no em dash is present (accepted trade-off).
- **Non-ASCII case folding**: rule substring matching MUST use a locale-aware case-insensitive comparison, while scoring and registry lookup MUST use plain `lowercased()`; a title that matches a rule under the locale-aware comparison can still fail a scoring comparison.
- **No contexts or no live windows**: `matchWindows` MUST return empty `matched`; with no live windows every dormant snapshot MUST be in `unmatchedSnapshots`; with no contexts every live window MUST be in `unassignedWindows`.
- **Stale live snapshot**: a snapshot whose `windowID` names a window not in `liveWindows` MUST NOT be re-matched (it is not dormant) and MUST NOT appear in `unmatchedSnapshots`.
- **Duplicate snapshot IDs across contexts**: acceptance MUST be keyed by `snapshotID` alone, so once one is matched every other dormant snapshot with the same ID MUST be treated as matched and omitted from `unmatchedSnapshots`. Snapshot IDs are generated UUIDs, so this arises only from corrupted or hand-built data.
- **Duplicate window IDs in `liveWindows`**: at most one of them MUST be matched; the duplicates MUST all be omitted from `unassignedWindows` once one is matched.
- **Threshold at or below 0**: every scored pair, including 0-score pairs, MUST become a candidate, so any dormant snapshot can be matched to any window, including a different app's.
- **Threshold above 90**: nothing MUST be matched.
- **Missing heuristics file**: `loadRules()` MUST return [] rather than throw.
- **Corrupt or unreadable heuristics file**: `loadRules()` MUST throw; the store does not repair or back up the file.
- **Unwritable root directory**: `saveRules(_:)` MUST throw the file-system error; with the atomic write, the prior file MUST remain intact.
- **Concurrent registry mutation**: each registry call MUST be atomic; a `matchWindows` run concurrent with `registerCustomRules` MAY score pairs against a mix of old and new rules (see registry-no-cross-call-snapshot).
- **Concurrent store access**: not serialized; two processes or threads saving at once MUST each produce a complete file, with the last atomic write winning.
- **Cancellation and timeouts**: none; every operation is synchronous and runs to completion. Matching is O(dormant snapshots × candidate windows) score calls.
- **Offline or network state**: not applicable; the component performs no network I/O.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SystemWindowMatcher.init(registry:)` | `HeuristicRegistry` | `HeuristicRegistry.shared` | Heuristic lookup used for fingerprinting and live-pattern extraction |
| `matchWindows(threshold:)` | `Int` | `autoAssignThreshold` (80) | Minimum score for a pair to be matched |
| `SystemWindowMatcher.autoAssignThreshold` | `Int` (static let) | 80 | Default auto-assign threshold |
| `SystemWindowMatcher.minSubstringPatternLength` | `Int` (static let) | 2 | Minimum stored-pattern length for a 60-point containment match |
| `HeuristicRegistry.init(heuristics:)` | `[AppHeuristic]?` | nil (the five built-ins) | Initial heuristics |
| `HeuristicRegistry.registerCustomRules(_:)` | `[CustomHeuristicRule]` | none registered | User rules layered over the initial heuristics |
| `CustomHeuristicStore.init(rootDirectory:)` | `URL` | required | Directory holding `heuristics.json` (the toolkit's manager passes its state store's root) |
| `CustomHeuristicRule.matchMode` | `CustomMatchMode` | `.substring` | How `titlePattern` is interpreted |
| `CustomHeuristicRule.autoAssign` | `Bool` | false | Auto-assign flag, read by the context manager (see rule-auto-assign) |
| `CustomHeuristicRule.targetContextName` | `String?` | nil | Auto-assign target context name (see rule-auto-assign) |
| `CustomHeuristicRule.name` | `String` | `"<appName> - <titlePattern>"` | Display name |

No environment variables or settings keys are read.

## Deep Linking

Not applicable: the matching engine and rule store expose no URL routes; they are called in-process by `SystemWindowContextManager`.

## Localization

The component contains user-facing English literals with no localization:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | Substring | `CustomMatchMode.displayName` for `.substring` |
| (none — hardcoded) | Regex | `CustomMatchMode.displayName` for `.regex` |
| (none — hardcoded) | `<appName> - <titlePattern>` | Default `CustomHeuristicRule.name`, shown in Settings |

The built-in heuristic `name` values (for example "Terminal") are also hardcoded. Log messages are developer-facing and not localized.

## Accessibility Options

Not applicable: the component renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: no code path in the matching sources is gated by a flag; custom rules and the threshold are ordinary parameters.

## Analytics

Not applicable: the matching sources emit no analytics events.

## Privacy

- **Data collected**: window owner names and titles are read in memory from the `SystemWindowInfo` values the caller passes; titles can contain document names, page titles and hostnames.
- **Storage**: only user-authored `CustomHeuristicRule` values are persisted, as plain JSON in `rootDirectory/heuristics.json`; fingerprints are persisted by the caller's context store, not by this component.
- **Transmission**: nothing leaves the device.
- **Retention**: `heuristics.json` persists until overwritten by `saveRules` or deleted by `removeAll`.
- **Logs**: invalid-regex errors log the pattern with `privacy: .public`; the window title is not logged.

## Logging

Subsystem: the host app's bundle identifier (`Bundle.main.bundleIdentifier`, or "nil") | Category: the type name (`CustomHeuristicRule`, `SystemWindowMatcher`) via `Loggable`

| Event | Level | Message |
|-------|-------|---------|
| Rule regex fails to compile in `matchTitle` | error | `Invalid custom-rule regex '<pattern>': <reason>` |
| Fingerprint regex fails to compile in scoring | error | `Invalid title regex '<pattern>': <reason>` |

`CustomHeuristicStore` and `HeuristicRegistry` do not log; store errors are thrown to the caller.

## Platform Notes

- **SwiftUI**: No view code; the source is plain Swift in `Core/SystemWindows/Matching/` built on Foundation (`NSRegularExpression`, `JSONEncoder`/`JSONDecoder`, `FileManager`, `NSLock`) and `os.Logger` via `Loggable`. `AppHeuristic.swift` holds the protocol and `HeuristicTitleParser`; `CustomHeuristicRule.swift` the rule and `CustomMatchMode`; `CustomHeuristic.swift` the adapter; `CustomHeuristicStore.swift` the JSON store; `HeuristicRegistry.swift` the locked registry; `SystemWindowMatcher.swift` fingerprinting, scoring and greedy assignment. A SwiftUI host drives it from an `@MainActor` model, as `SystemWindowContextManager` does. Swift's `Regex` could replace `NSRegularExpression`, but the case-insensitive flag, the non-empty-match rule and UTF-16 range mapping must be preserved.
- **Compose**: Port to plain Kotlin: an `interface AppHeuristic` with default methods, `data class` rule with `kotlinx.serialization` (ISO 8601 via `Instant`), `java.util.regex.Pattern` with `CASE_INSENSITIVE` (add `UNICODE_CASE` to approximate Foundation), a `ReentrantLock` or `synchronized` registry, and `Files.move(..., ATOMIC_MOVE)` for the atomic save. `String.lowercase()` matches Swift's `lowercased()`; use `contains(ignoreCase = true)` for the locale-aware rule comparison. Use `sortedWith(compareByDescending { score }.thenBy { contextId.toString() }...)`; Kotlin's sort is stable, but keep the explicit tie-breakers for parity.
- **React/Web**: TypeScript: `interface AppHeuristic`, a `Map<string, AppHeuristic>` keyed by `toLowerCase()`, `new RegExp(pattern, "i")` (JS regex syntax differs from ICU; `\d`, groups and anchors port, possessive quantifiers and some Unicode classes do not), and `JSON.stringify` with a key-sorting replacer. The registry needs no lock in single-threaded JS. Persistence goes to `localStorage`/IndexedDB or a Node `fs.writeFile` to a temp file then `rename`. `Array.prototype.sort` is stable, but keep the four-key comparator. Compare UUIDs by their uppercase string form to match `uuidString` ordering.
- **AppKit / UIKit**: The same Core sources compile unchanged for AppKit hosts; window data comes from `CGWindowListCopyWindowInfo` (owner name, title, display). UIKit has no cross-app window list, so on iOS only the rule, store and registry types are meaningful, and there are no live windows to match.
- **WinUI 3**: Port to .NET in a class library with no XAML. `AppHeuristic` becomes an `interface IAppHeuristic` with default interface methods for `RecommendedStrategy` and `FingerprintPattern` (returning a `(string Pattern, MatchStrategy Strategy)?` tuple). `CustomHeuristicRule` becomes a `record` serialized with `System.Text.Json` (`JsonSerializerOptions { WriteIndented = true }`, `JsonStringEnumConverter` with camelCase so `"substring"`/`"regex"` round-trip; ISO 8601 `DateTimeOffset` is the default). Sorted keys are not built in, so either order properties with `[JsonPropertyOrder]` alphabetically or accept a different on-disk order. `CustomHeuristicStore` uses `Windows.Storage.ApplicationData.Current.LocalFolder` (packaged) or a caller-given `DirectoryInfo`, `Directory.CreateDirectory`, and an atomic save via write-to-temp then `File.Replace`/`File.Move(overwrite: true)`; its methods may become `Task`-returning `async` with `StorageFile` APIs, which changes the synchronous contract. `HeuristicRegistry` uses a `Dictionary<string, IAppHeuristic>(StringComparer.OrdinalIgnoreCase)` guarded by `lock` (or `ReaderWriterLockSlim`); note `OrdinalIgnoreCase` differs slightly from Swift `lowercased()` for some non-ASCII characters. Regex uses `System.Text.RegularExpressions.Regex` with `RegexOptions.IgnoreCase | RegexOptions.CultureInvariant` and a `Match.Length > 0` check; cache compiled regexes if desired, since .NET has no equivalent of the per-call log. Window data comes from `EnumWindows`/`GetWindowText`/`GetWindowThreadProcessId` plus `MonitorFromWindow` for `display`, with the process name as `app`. If the rule list is bound to a Settings page, expose it as an `ObservableCollection<CustomHeuristicRule>` and raise `INotifyPropertyChanged` on the view model, calling `RegisterCustomRules` after each change. Sort candidates with `OrderByDescending(c => c.Score).ThenBy(c => c.ContextId.ToString("D").ToUpperInvariant(), StringComparer.Ordinal)...`.

## Design Decisions

**Decision**: Regex custom rules fingerprint by the regex source with `.appAndTitleRegex`, not by the captured text.
**Rationale**: Per the `CustomHeuristic.fingerprintPattern` comment, comparing one window's captured value ("JIRA-1234") against a sibling's ("JIRA-9999") would never match, so the whole title family must re-match after restart.
**Approved**: pending

**Decision**: Substring matching requires a stored pattern of at least 2 characters and tests only "live contains stored".
**Rationale**: The source says a 1-character pattern would match nearly every window of an app, and the reverse direction "admitted unrelated windows as 60-pt matches" and was dropped.
**Approved**: pending

**Decision**: Zero-width regex matches are rejected in both the rule and the matcher.
**Rationale**: Per the source, patterns such as `.*` or `^` would otherwise match every title and extract an empty pattern.
**Approved**: pending

**Decision**: Invalid regexes log an error instead of failing silently.
**Rationale**: The `regexMatches` comment says a corrupt fingerprint should not be mistaken for "no match" and the window orphaned forever without a signal. The regex is recompiled on each call, so the error repeats per scored pair.
**Approved**: pending

**Decision**: Candidate ordering uses explicit tie-breakers (context UUID string, snapshot UUID string, window ID).
**Rationale**: Swift's `Array.sort` is not guaranteed stable, so equal scores need a fixed order for reproducible greedy assignment across runs.
**Approved**: pending

**Decision**: Sub-threshold pairs are dropped before assignment rather than competing in the greedy pass.
**Rationale**: Per the source comment, their snapshot and window stay in `unmatchedSnapshots`/`unassignedWindows` "for manual handling" instead of being silently consumed. A consequence is that substring-containment matches (60 or 70) are never auto-assigned at the default threshold of 80.
**Approved**: pending

**Decision**: The en dash is accepted as a title separator alongside the em dash.
**Rationale**: Some locales and builds render an en dash; the cost (splitting content containing " – ") is accepted because content en dashes are rare, per the `HeuristicTitleParser` NOTE.
**Approved**: pending

**Decision**: Custom rules override built-ins by replacing the lookup entry, and `isBuiltIn` reports a built-in app as user-defined once a custom rule targets it.
**Rationale**: Per `isBuiltIn`, a user override makes the rule deletable in Settings even when a built-in also targets that app. The same last-wins mapping is what leaves the earlier of two same-app custom rules unused by the registry (see duplicate-app-rules).
**Approved**: pending

**Decision**: The store takes its directory from the caller.
**Rationale**: Per the `CustomHeuristicStore` doc comment, the toolkit must not hardcode an application-specific directory.
**Approved**: pending

**Decision**: Rule substring matching uses a locale-aware case-insensitive comparison, while scoring uses `lowercased()`.
**Rationale**: No rationale is stated in the source; the divergence is recorded so ports reproduce it rather than unify it by accident.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |

`separation-of-concerns` passes: parsing (`AppHeuristic`, `HeuristicTitleParser`), user rules, persistence (`CustomHeuristicStore`), lookup (`HeuristicRegistry`) and scoring/assignment (`SystemWindowMatcher`) are separate types, and applying match results is left to `SystemWindowContextManager`. `unit-test-coverage` is partial: `SystemWindowMatcherTests` covers the app gate, appOnly, the substring length guard, substring and regex scoring, the display bonus, threshold filtering, deterministic ties and `MatchResult` equality, and `HeuristicTests` covers the separators, custom-rule fingerprinting and `isBuiltIn`; nothing tests `CustomHeuristicStore`, `.appAndTitleExact` scoring, the fingerprint fallback, invalid regexes or `registerCustomRules` replacement. `explicit-error-handling` passes because store failures are thrown to the caller and invalid regexes are logged rather than swallowed. `no-hardcoded-strings` fails because `CustomMatchMode.displayName` and the default rule name are English literals shown in Settings. `data-integrity` is partial because rules are never validated: an invalid regex or empty app name is accepted and saved, and two rules for the same app leave one silently unused. `no-pii-in-logs` passes because only the user-authored regex pattern is logged, never a window title.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from the AgenticToolkit Core SystemWindows Matching sources |
