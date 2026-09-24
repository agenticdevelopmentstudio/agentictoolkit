---
id: a29c23d4-a086-4413-9843-6b319e340646
title: ActivationEventMatcher
domain: agentictoolkit://recipes/extension-host-core-extensions-activation-event-matcher
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Parses a VS Code extension manifest's activationEvents into typed triggers,
  resolves workspaceContains globs, and decides whether a trigger activates the extension.
platforms:
- swift
- macos
tags:
- extension-host
- activation-events
- glob-matching
- vscode-compatibility
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/Core/Extensions/ActivationEventMatcher.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionManifest.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/VSCodeEngineRange.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SemanticVersion.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/ActivationEventMatcherTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/ExtensionHostInstaller.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ActivationEventMatcher

## Overview

`ActivationEventMatcher` is `AgenticToolkitCore`'s parser and query engine for
a VS Code extension manifest's `activationEvents` array. Per its own doc
comment, it exists so a host does not "re-parse the same five prefixes at
every call site." Together with its supporting types it is the whole
activation-matching contract: `ActivationEvent` parses one manifest entry
into a typed `Kind`; `ActivationTrigger` names a thing that just happened in
the host (startup finished, a document opened, a command invoked, a webview
panel restored, a contributed view shown, or a workspace scan completed);
`WorkspaceScan` is one directory walk's paths, decomposed once for reuse
across every extension checked against it; the file-local `GlobPattern` is a
backtracking matcher for `workspaceContains:` globs; and
`ActivationEventMatcher` itself, built once per installed extension from its
`ExtensionManifest`, answers `matches(_:)` for any `ActivationTrigger` and
also implements VS Code 1.74's "implicit activation from
`contributes.commands`" rule. `ExtensionHostInstaller.swift` is the sole
production caller today: it builds one matcher per `ExtensionHostInstallation`
at construction (`self.activationMatcher = ActivationEventMatcher(manifest:
loadedExtension.manifest)`) and queries it repeatedly as startup, document-
open, command-invocation, view-shown and workspace-scan triggers occur.

## Behavioral Requirements

- **event-kind-cases**: `ActivationEvent.Kind` MUST expose exactly seven
  cases: `any` (`"*"`), `startupFinished` (`"onStartupFinished"`),
  `language(String)` (`"onLanguage:swift"` to `"swift"`),
  `command(String)` (`"onCommand:foo.bar"` to `"foo.bar"`),
  `workspaceContains(String)` (`"workspaceContains:**/*.csproj"` to the
  glob), `webviewPanel(String)` (`"onWebviewPanel:markdown.preview"` to the
  view type), and `view(String)` (`"onView:package-explorer"` to the view
  id).
- **event-value-semantics**: `ActivationEvent` and `ActivationTrigger` MUST
  be `Sendable`, `Equatable` value types; `ActivationEvent.Kind` MUST also be
  `Sendable` and `Equatable`.
- **raw-value-preservation**: `ActivationEvent.rawValue` MUST hold the entry
  exactly as the manifest spelled it — including any leading or trailing
  whitespace — even though recognition of the entry's shape operates on a
  trimmed copy; the doc comment states this is so a diagnostic can quote
  what the author wrote.
- **whitespace-trimming**: `ActivationEvent.init(rawValue:)` MUST trim
  leading and trailing whitespace (Foundation's `.whitespaces` character
  set) before recognizing the entry's shape.
- **entry-parsing-order**: `init(rawValue:)` MUST test the trimmed value, in
  order, against: empty (fails), exactly `"*"`, exactly
  `"onStartupFinished"`, then the prefixes `"onLanguage:"`, `"onCommand:"`,
  `"workspaceContains:"`, `"onWebviewPanel:"`, `"onView:"`; the first match
  wins.
- **empty-entry-rejection**: An entry that trims to the empty string MUST
  fail to parse (`init(rawValue:)` returns `nil`).
- **prefixed-payload-extraction**: For each of the five colon-prefixed
  forms, the payload MUST be everything after the prefix, taken verbatim
  and never case-normalized — the doc comment explains that VS Code
  language and command ids are lowercase by convention but the editor never
  enforces it, so normalizing here would accept manifests VS Code itself
  would not activate.
- **empty-payload-rejection**: A prefixed entry whose payload is empty after
  the colon (for example `"onLanguage:"`) MUST fail to parse rather than
  being read as a match against the empty string.
- **unrecognized-entry-rejection**: A trimmed value matching none of the
  seven recognized shapes MUST cause `init(rawValue:)` to return `nil`.
- **matcher-value-semantics**: `ActivationEventMatcher` MUST be `Sendable`
  and `Equatable`.
- **parse-triage**: `ActivationEventMatcher.init(manifest:)` MUST parse
  every entry of `manifest.activationEvents`, in order, placing every entry
  that parses into `events` (in original manifest order) and the raw,
  untrimmed text of every entry that fails to parse into
  `unrecognizedEvents` (in original manifest order); an unrecognized entry
  MUST NOT be dropped silently.
- **eager-activation-flag**: `activatesEagerly` MUST be `true` if and only if
  `events` contains an entry whose `kind` is `.any`.
- **glob-triage**: For every parsed `.workspaceContains(glob)` event, in
  order, `init(manifest:)` MUST attempt to build a `GlobPattern` from the
  glob text; a glob that parses MUST be added to the matcher's internal
  pattern list (used to answer `.workspaceScanned` triggers), and a glob
  that fails to parse MUST have its raw payload text (not the
  `"workspaceContains:"` prefix) appended to `unsupportedPatterns`, in
  order; a pattern in `unsupportedPatterns` MUST NOT ever match.
- **glob-syntax-supported**: A supported `workspaceContains:` glob's syntax
  is: a literal character matches itself; `?` matches exactly one character
  other than a path separator; `*` matches a run of zero or more characters
  excluding a path separator; two consecutive `*` characters that begin and
  end a whole path segment — starting the pattern or preceded by a path
  separator, and ending the pattern or followed by a path separator — match
  zero or more whole path segments, crossing path separators; two
  consecutive `*` characters that do not form a whole segment (for example
  a run that starts mid-segment or ends mid-segment) are treated as a
  single `*`; and a brace group of comma-separated alternatives (an
  alternative MAY be empty) matches if any one alternative matches, but a
  brace group MUST NOT contain a nested brace group.
- **glob-syntax-unsupported**: A `workspaceContains:` glob containing a
  square-bracket character class, or one beginning with an exclamation-mark
  negation, MUST fail to parse (`GlobPattern.init` returns `nil`) rather
  than being approximated as a literal or a partial match; the doc comment
  states that treating an unsupported construct as a literal "would make a
  pattern match paths its author never intended."
- **glob-anchoring**: A parsed `GlobPattern` MUST match a path only when the
  pattern consumes the whole path at both ends; a partial or substring
  match MUST NOT count as a match.
- **glob-character-granularity**: `GlobPattern` matching MUST operate over
  Swift `Character` (extended grapheme cluster) elements of both the
  pattern and the path, never Unicode scalars or UTF-8/UTF-16 code units.
- **workspace-scan-decomposition**: `WorkspaceScan.init(relativePaths:)`
  MUST decompose every entry of `relativePaths` into its `Character` array
  exactly once, at construction, storing the result in `decomposedPaths` at
  the matching index; this decomposition MUST NOT be repeated per pattern
  or per extension checked against the same scan.
- **workspace-scan-equality**: Two `WorkspaceScan` values MUST be equal if
  and only if their `relativePaths` arrays are equal; `decomposedPaths`
  (a derived index) MUST NOT participate in equality.
- **workspace-scan-reuse**: A caller that checks more than one
  `ActivationEventMatcher` against the same directory walk MUST construct
  one shared `WorkspaceScan` and pass it to every `matches(.workspaceScanned(_:))`
  call, rather than building a fresh `WorkspaceScan` per extension; the doc
  comment on `WorkspaceScan` gives the concrete cost of not doing so (a
  20,000-path workspace with 30 installed extensions decomposing 600,000
  paths on the main actor for input that never changed between calls).
- **implicit-activation-floor**: `implicitlyActivatingCommands` MUST equal
  the set of `manifest.contributes?.commands` command-id strings when
  `manifest.engines.vscode` parses into a `VSCodeEngineRange` that is either
  `isUnconstrained` (for example `"*"`) or whose `minimumVersion` is greater
  than or equal to 1.74.0; otherwise `implicitlyActivatingCommands` MUST be
  empty. The version tested is the manifest's own declared engine, never
  the host's, because an extension that still targets an older VS Code
  cannot rely on behavior its stated minimum predates.
- **implicit-activation-unparseable-engine**: A manifest whose
  `engines.vscode` does not parse into a `VSCodeEngineRange` MUST yield an
  empty `implicitlyActivatingCommands` set; an engine string this component
  cannot evaluate MUST NOT be treated as evidence the extension supports
  the newer inference.
- **command-match**: `matches(.commandInvoked(commandID))` MUST return
  `true` if and only if `commandID` is a member of
  `implicitlyActivatingCommands`, or `events` contains an entry whose
  `kind` is `.command(commandID)` (exact, case-sensitive match); otherwise
  it MUST return `false`.
- **document-opened-match**: `matches(.documentOpened(languageID:))` MUST
  return `true` if and only if `events` contains an entry whose `kind` is
  `.language(declared)` with `declared` exactly equal (case-sensitive) to
  `languageID`.
- **startup-match**: `matches(.startupFinished)` MUST return `true` if and
  only if `events` contains an entry whose `kind` is `.startupFinished`.
- **webview-panel-restored-match**: `matches(.webviewPanelRestored(viewType:))`
  MUST return `true` if and only if `events` contains an entry whose `kind`
  is `.webviewPanel(declared)` with `declared` exactly equal
  (case-sensitive) to `viewType`.
- **view-shown-match**: `matches(.viewShown(viewID:))` MUST return `true`
  if and only if `events` contains an entry whose `kind` is `.view(declared)`
  with `declared` exactly equal (case-sensitive) to `viewID`.
- **workspace-scanned-match**: `matches(.workspaceScanned(scan))` MUST
  return `false` immediately when the matcher's parsed
  `workspaceContains:` pattern list is empty; otherwise it MUST return
  `true` if and only if at least one of `scan.decomposedPaths` matches at
  least one parsed pattern.
- **eager-short-circuit**: When `activatesEagerly` is `true`, `matches(_:)`
  MUST return `true` for every `ActivationTrigger` case without evaluating
  any other rule.
- **webview-panel-ownership-exclusion**: `declaresWebviewPanel(viewType:)`
  MUST NOT consult `activatesEagerly`; it MUST return `true` if and only if
  `events` contains an entry whose `kind` is `.webviewPanel(declared)` with
  `declared` exactly equal (case-sensitive) to `viewType`, regardless of
  whether the manifest also declares `"*"`. The doc comment states the
  reason: activating eagerly is "does this wake the extension," while
  owning a view type is "whose panel is this," and an extension that only
  activates eagerly has made no claim on any view type — handing it
  someone else's panel would be a silent mis-delivery.
- **empty-manifest-no-match**: A matcher built from a manifest with no
  `activationEvents` entries and no implicitly activating commands MUST
  have `activatesEagerly == false`, and `matches(_:)` MUST return `false`
  for every `ActivationTrigger` case; an extension with no recognized
  events and no implicitly activating commands MUST NOT fall back to eager
  activation.
- **backtracking-memoization**: `GlobPattern.matches(_:)` SHOULD memoize
  search state — on the pair of token index and path index for the
  pattern's own tokens, and on the triple of branch id, branch-internal
  index and path index for each brace-group branch — whenever the pattern
  contains more than one token capable of consuming a variable amount of
  the path (a lone `*`, a whole-segment double-`*`, or a brace-group
  alternation, each alternation counted together with its own contained
  tokens); a pattern with at most one such token MAY skip memoization,
  since every search state is then reached exactly once regardless. See
  Design Decisions for the rationale.
- **single-matcher-trigger-factory**: `ActivationTrigger.workspaceScanned(relativePaths:)`
  MAY be used by a caller that has exactly one matcher to ask (a test, or a
  replay for a single extension with no prepared scan to hand); the
  `workspace-scan-reuse` requirement's prohibition applies only to a caller
  with more than one matcher.

## Appearance

Not applicable — this is a pure activation-event parser and matcher, not a
visual component.

## States

Not applicable — this is a pure activation-event parser and matcher, not a
visual component.

## Accessibility

Not applicable — this is a pure activation-event parser and matcher, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| aem-001 | event-kind-cases, glob-triage | `ActivationEvent(rawValue: "*")` | `kind == .any`; `rawValue == "*"` |
| aem-002 | entry-parsing-order | `ActivationEvent(rawValue: "onStartupFinished")` | `kind == .startupFinished` |
| aem-003 | prefixed-payload-extraction | `ActivationEvent(rawValue: "onLanguage:swift")` | `kind == .language("swift")` |
| aem-004 | prefixed-payload-extraction | `ActivationEvent(rawValue: "onCommand:foo.bar")` | `kind == .command("foo.bar")` |
| aem-005 | prefixed-payload-extraction | `ActivationEvent(rawValue: "onWebviewPanel:markdown.preview")` | `kind == .webviewPanel("markdown.preview")` |
| aem-006 | empty-payload-rejection | `ActivationEvent(rawValue: "onLanguage:")`, `"onCommand:"`, `"workspaceContains:"`, `"onWebviewPanel:"`, `"onView:"` | each is `nil` |
| aem-007 | empty-entry-rejection, unrecognized-entry-rejection | `ActivationEvent(rawValue: "")`, `"   "`, `"onDebug"` | each is `nil` |
| aem-008 | whitespace-trimming | `ActivationEvent(rawValue: "  onStartupFinished  ")` | `kind == .startupFinished`; `rawValue == "  onStartupFinished  "` |
| aem-009 | parse-triage, eager-activation-flag | manifest `activationEvents: ["onStartupFinished", "onDebug", "onLanguage:swift"]` | `events` holds the two recognized entries in order; `unrecognizedEvents == ["onDebug"]`; `activatesEagerly == false` |
| aem-010 | eager-activation-flag, eager-short-circuit | manifest `activationEvents: ["*"]` | `activatesEagerly == true`; `matches(.startupFinished)`, `matches(.documentOpened(languageID: "swift"))`, `matches(.commandInvoked("anything"))` and `matches(.workspaceScanned(WorkspaceScan(relativePaths: [])))` are all `true` |
| aem-011 | startup-match | manifest `activationEvents: ["onStartupFinished"]` | `matches(.startupFinished) == true`; `matches(.documentOpened(languageID: "swift")) == false` |
| aem-012 | document-opened-match | manifest `activationEvents: ["onLanguage:swift"]` | `matches(.documentOpened(languageID: "swift")) == true`; `matches(.documentOpened(languageID: "Swift")) == false` (case-sensitive) |
| aem-013 | command-match | manifest `activationEvents: ["onCommand:a.b"]` | `matches(.commandInvoked("a.b")) == true`; `matches(.commandInvoked("a")) == false` |
| aem-014 | empty-manifest-no-match | manifest with empty `activationEvents` and no `contributes.commands` | `activatesEagerly == false`; `matches(_:)` is `false` for `.startupFinished`, `.documentOpened(languageID: "swift")`, `.commandInvoked("x")` and `.workspaceScanned(WorkspaceScan(relativePaths: ["a"]))` |
| aem-015 | implicit-activation-floor, command-match | manifest with `engines.vscode: "^1.74.0"`, `contributes.commands: [{command: "x.run", ...}]`, no `onCommand:` entry | `implicitlyActivatingCommands == ["x.run"]`; `matches(.commandInvoked("x.run")) == true` |
| aem-016 | implicit-activation-floor | same manifest with `engines.vscode: "^1.73.0"` | `implicitlyActivatingCommands` is empty; `matches(.commandInvoked("x.run")) == false` |
| aem-017 | implicit-activation-floor | same manifest with `engines.vscode: "*"` | `implicitlyActivatingCommands == ["x.run"]` (an unconstrained engine takes the same branch as a modern floor, per the source's own note on `*` not being a declared minimum of 0.0.0) |
| aem-018 | implicit-activation-unparseable-engine | same manifest with `engines.vscode: "~1.74.0"` (a shape `VSCodeEngineRange` does not parse) | `implicitlyActivatingCommands` is empty; `matches(.commandInvoked("x.run")) == false` |
| aem-019 | command-match | manifest with `engines.vscode: "^1.60.0"`, `activationEvents: ["onCommand:x.run"]`, `contributes.commands: [{command: "x.run", ...}]` | `implicitlyActivatingCommands` is empty, yet `matches(.commandInvoked("x.run")) == true` (the explicit `onCommand:` entry matches independently of the implicit-activation floor) |
| aem-020 | glob-syntax-supported, glob-anchoring | pattern `"*.csproj"` vs path `"a.csproj"` | matches; vs path `"src/a.csproj"` | does not match (a single `*` never crosses a path separator) |
| aem-021 | glob-syntax-supported | pattern with a leading whole-segment double-`*` followed by a separator, then `*.csproj`, vs path `"a.csproj"` | matches; vs a deeply nested path ending in `.csproj` | matches (the whole-segment double-`*` crosses separators) |
| aem-022 | glob-syntax-supported | pattern `"?.txt"` vs path `"a.txt"` | matches; vs path `"ab.txt"` | does not match |
| aem-023 | glob-syntax-supported | a brace group of two comma-separated alternatives (for example `package.json` or `bower.json`) vs each alternative's exact filename | matches both; vs an unrelated filename | does not match |
| aem-024 | glob-syntax-unsupported | pattern `"[abc].txt"` | `GlobPattern.init` returns `nil`; the raw text `"[abc].txt"` is appended to `unsupportedPatterns`; `matches(.workspaceScanned(...))` never matches it |
| aem-025 | glob-syntax-unsupported | pattern beginning with `"!"` | `GlobPattern.init` returns `nil`; raw text appended to `unsupportedPatterns` |
| aem-026 | glob-anchoring | pattern `"a.txt"` vs path `"axtxt"` | does not match (no substring match) |
| aem-027 | workspace-scanned-match | pattern that parses, `WorkspaceScan(relativePaths: [])` (empty scan) | `matches(.workspaceScanned(scan)) == false` |
| aem-028 | backtracking-memoization | an adversarial pattern with several whole-segment double-`*` tokens separated by literal `a` characters and ending in a literal `b`, matched against a long run of `a` characters with no trailing `b` | resolves to `false` without an exponential increase in search time as more double-`*` segments are added |
| aem-029 | webview-panel-restored-match | manifest `activationEvents: ["onWebviewPanel:markdown.preview"]` | `matches(.webviewPanelRestored(viewType: "markdown.preview")) == true`; `matches(.webviewPanelRestored(viewType: "markdown.other")) == false` |
| aem-030 | webview-panel-ownership-exclusion | manifest `activationEvents: ["*"]` | `matches(.webviewPanelRestored(viewType: "markdown.preview")) == true`, but `declaresWebviewPanel(viewType: "markdown.preview") == false` |
| aem-031 | webview-panel-ownership-exclusion | manifest `activationEvents: ["onStartupFinished", "onWebviewPanel:markdown.preview"]` | `declaresWebviewPanel(viewType: "markdown.preview") == true`; `declaresWebviewPanel(viewType: "markdown.Preview") == false` (case-sensitive); `declaresWebviewPanel(viewType: "") == false` |
| aem-032 | view-shown-match | manifest `activationEvents: ["onView:explorer"]` | `matches(.viewShown(viewID: "explorer")) == true`; `matches(.viewShown(viewID: "other")) == false`. Source-only: `ActivationEventMatcherTests.swift` covers `onView:` parsing into `.view("explorer")` but has no dedicated `matches(.viewShown(_:))` assertion; this vector is traced to `ActivationEventMatcher.matches(_:)`'s `.viewShown` case, which follows the exact same pattern as the tested `.webviewPanelRestored` case. |

## Edge Cases

- **Null/empty input**: an empty `activationEvents` array, or one containing
  only entries that fail to parse, yields an empty `events` array,
  `activatesEagerly == false`, and (per `empty-manifest-no-match`) no
  trigger matches. An entry that trims to the empty string, or a prefixed
  entry with an empty payload, is rejected rather than treated as a
  wildcard or an empty-string match (`empty-entry-rejection`,
  `empty-payload-rejection`).
- **Malformed glob syntax**: a `workspaceContains:` glob using a
  square-bracket character class or a leading exclamation-mark negation is
  rejected at parse time and recorded in `unsupportedPatterns`; it never
  matches, and it never causes `ActivationEventMatcher.init(manifest:)` to
  fail or throw (`glob-syntax-unsupported`, `glob-triage`).
- **Malformed engine range**: an `engines.vscode` string this component
  cannot parse (anything outside `*`, an optional `^`/`>=` prefix, and
  three numeric-or-`x` components) yields an empty
  `implicitlyActivatingCommands`, never a crash or a `nil` matcher
  (`implicit-activation-unparseable-engine`).
- **Boundary values — implicit-activation floor**: an engine of exactly
  `"1.74.0"` or `"^1.74.0"` grants implicit activation; an engine one patch
  below the floor (`"^1.73.0"`, or any range whose `minimumVersion` is less
  than 1.74.0) does not; an unconstrained engine (`"*"`) grants it, because
  the source explicitly treats "no version claim" as distinct from "a
  claim to predate 1.74" (`implicit-activation-floor`).
- **Boundary values — glob anchoring**: a pattern must consume the entire
  path at both ends; a pattern that matches a prefix or suffix of a path
  but not the whole of it does not match (`glob-anchoring`).
- **Concurrent access**: `ActivationEvent`, `ActivationTrigger`,
  `WorkspaceScan`, and `ActivationEventMatcher` are declared `Sendable`
  value types with no mutable stored state reachable after
  construction, and `GlobPattern.matches(_:)` builds its memoization
  tables as local variables scoped to that one call rather than shared
  mutable state on the pattern — so `matches(_:)` MAY be called
  concurrently, from any isolation domain, against the same matcher or the
  same `GlobPattern`, with no synchronization required.
- **Error states**: not applicable — every operation in this component is a
  synchronous, non-throwing, pure computation over already-in-memory
  values; there is no I/O, so there is no error channel to define.
- **Offline/disconnected**: not applicable — this component performs no
  networking and touches no filesystem; `WorkspaceScan`'s paths are
  supplied by the caller, who is responsible for the directory walk that
  produced them.
- **Unbounded input size**: `matches(.workspaceScanned(_:))` and
  `GlobPattern.matches(_:)` define no timeout, cancellation, or size limit;
  matching runs synchronously to completion regardless of how many paths a
  `WorkspaceScan` carries or how many backtracking tokens a pattern
  contains (mitigated for cost, not bounded for time, by
  `backtracking-memoization`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `manifest` | `ExtensionManifest` | none (required) | Supplies `activationEvents`, `engines.vscode`, and `contributes.commands` to `ActivationEventMatcher.init(manifest:)`; there is no default manifest. |
| `trigger` | `ActivationTrigger` | none (required) | The event `matches(_:)` is asked about; one of `.startupFinished`, `.documentOpened(languageID:)`, `.commandInvoked(_:)`, `.webviewPanelRestored(viewType:)`, `.viewShown(viewID:)`, `.workspaceScanned(_:)`. |
| `relativePaths` | `[String]` | none (required, when using `WorkspaceScan`) | Workspace-relative paths, `/`-separated with no leading slash, that a caller's directory walk produced; supplied once per scan via `WorkspaceScan.init(relativePaths:)` or the `ActivationTrigger.workspaceScanned(relativePaths:)` convenience factory. |

There are no environment variables, settings keys, or injected dependencies:
`ActivationEventMatcher` and its supporting types take every input as a
plain constructor or method argument and read no ambient state.

## Deep Linking

Not applicable: this component parses and matches manifest strings in
memory; it defines no URL scheme, route, or navigable destination.

## Localization

Not applicable: this component produces no user-facing strings. It carries
manifest text (`unrecognizedEvents`, `unsupportedPatterns`, language and
command ids) verbatim for a caller to report, but formats or localizes
none of it itself.

## Accessibility Options

Not applicable: this component has no visual or interactive surface for a
system accessibility display option to affect.

## Feature Flags

Not applicable: `ActivationEventMatcher.swift` defines no feature flag,
build configuration check, or remote-config lookup; its behavior is fixed
by the manifest it is constructed with.

## Analytics

Not applicable: this component emits no analytics events; it returns
values to its caller and performs no telemetry of its own.

## Privacy

- **Data collected**: none. `ActivationEventMatcher` reads only the
  `activationEvents`, `engines.vscode`, and `contributes.commands` fields
  of a caller-supplied `ExtensionManifest`, and the `relativePaths` of a
  caller-supplied `WorkspaceScan`; none of this is device- or user-identifying
  data, and the component collects nothing beyond what its caller already
  handed it.
- **Storage**: none. Every value is held only in the in-memory
  `ActivationEventMatcher`/`WorkspaceScan` instance for the duration the
  caller keeps it; nothing is written to disk by this component.
- **Transmission**: none. This component performs no networking.
- **Retention**: for the lifetime of the `ActivationEventMatcher` or
  `WorkspaceScan` value the caller holds; releasing the value releases the
  data with it.

## Logging

Not applicable: `ActivationEventMatcher.swift` contains no logging call.
Entries it cannot recognize or match (`unrecognizedEvents`,
`unsupportedPatterns`) are surfaced as plain data for a caller to log or
report, rather than being logged by this component itself.

## Platform Notes

- **SwiftUI**: the source (`ActivationEventMatcher.swift`,
  `ExtensionManifest.swift`, `VSCodeEngineRange.swift`,
  `SemanticVersion.swift`) is plain Foundation logic — value types, string
  parsing, and a hand-rolled backtracking matcher — with no dependency on
  SwiftUI or any view-layer framework. A port that keeps this component in
  Swift needs nothing beyond `Foundation`.
- **Compose**: start from Kotlin `data class`/`sealed interface` for
  `ActivationEvent`/`ActivationTrigger` (a `sealed interface` models the
  `Kind`/`Trigger` enums with associated payloads more directly than a
  Kotlin `enum class`), plain `String` parsing for the prefix matching, and
  a hand-written recursive matcher for the glob logic — Kotlin's
  `Regex`/`glob` support does not implement VS Code's specific `**`
  whole-segment rule or its brace-alternation syntax, so translating glob
  to a JVM regex has the same escaping hazard the source's own doc comment
  gives for avoiding `NSRegularExpression`. Memoize with a plain
  `HashMap` keyed on the same `(tokenIndex, pathIndex)`/`(branchId,
  branchIndex, pathIndex)` shapes.
- **React/Web**: model `ActivationEvent`/`ActivationTrigger` as discriminated
  union types (a `kind` or `type` string field plus payload), parse
  `activationEvents` with the same ordered `if`/`else if` chain over
  `String.prototype.startsWith`, and port the glob matcher as a small
  recursive function over an array of tokens — `minimatch`/`micromatch`
  exist on npm but neither one, out of the box, restricts a bare `**` to
  crossing directories only when it is a whole path segment while treating
  every other `**` as a single `*`; that VS Code-specific rule (and the
  rejection of `[...]` classes and leading `!`) needs the same custom
  tokenizer the source implements, not a general-purpose glob library.
- **AppKit / UIKit**: identical to the SwiftUI note — the component depends
  on neither AppKit nor UIKit, so a macOS or iOS host consumes the same
  `AgenticToolkitCore` type directly with no translation.
- **WinUI 3**: there is no .NET or Windows App SDK type that already
  implements VS Code's `activationEvents` grammar or its `engines.vscode`
  range grammar, so both need a direct C# port rather than an existing
  library. Model `ActivationEvent`/`ActivationTrigger` as C# records with a
  discriminated `Kind`/`Trigger` (a base `abstract record` with derived
  records per case, or a single record carrying a `Kind` enum plus a
  nullable payload string) rather than reaching for `System.Text.Json`'s
  polymorphic serialization, since these values are constructed from
  parsed strings, not deserialized JSON. Port `VSCodeEngineRange` and
  `SemanticVersion` as plain C# `readonly struct`s with the same
  three-base/must-equal-flag representation — resist the temptation to
  reach for NuGet's `Semver` or `NuGet.Versioning` packages, since both
  implement npm/NuGet semver ranges, which is precisely the grammar the
  source's own doc comment says VS Code's `engines.vscode` is not. Port
  `GlobPattern` as a private nested class inside the equivalent of
  `ActivationEventMatcher` (mirroring the source's file-local placement)
  with its two memoization tables as `Dictionary<TKey, bool>` locals scoped
  to one `Matches` call, matching over a `char[]` (note: a C# `char` is a
  UTF-16 code unit, not a grapheme cluster the way a Swift `Character` is,
  so a path containing a combining-character sequence could tokenize
  differently between a Swift host and a WinUI 3 host — call this out in
  the port's own tests rather than assuming parity). `Task`/`async` and
  `ObservableCollection`/`INotifyPropertyChanged` have no role here: every
  operation is synchronous and returns a value rather than notifying of a
  change.

## Design Decisions

- **Decision**: Glob matching operates over Swift `Character` (extended
  grapheme cluster) elements rather than Unicode scalars or UTF-8/UTF-16
  code units.
  **Rationale**: `WorkspaceScan.decomposedPaths` and `GlobPattern.matches`
  are typed `[Character]` throughout the source; this is the natural
  granularity for `Array(String)` in Swift, and it means a path segment
  containing a multi-scalar grapheme cluster is compared as one unit on
  either side of the match. A port to a language whose native string
  iteration is UTF-16 code units (C#, JavaScript) or Unicode scalars needs
  to either replicate grapheme-cluster segmentation or explicitly accept
  that a combining-character path could tokenize differently — a
  divergence worth testing for, not assuming away.
  **Approved**: pending
- **Decision**: `GlobPattern` stays file-local to `ActivationEventMatcher.swift`
  rather than becoming its own file or a shared export.
  **Rationale**: the source's own doc comment states that `abstractr
  exports` has no glob, fnmatch, or wildcard matcher anywhere in the
  toolkit, and creating a second new file in the shared `apple-core` tier
  for a type with exactly one caller would trip the tier's placement gate
  for no benefit; the same comment names the moment to promote it (a
  second consumer, expected to be a future `workspace.findFiles`
  implementation).
  **Approved**: pending
- **Decision**: memoization of the backtracking search is conditional —
  enabled only when a pattern contains more than one backtracking-capable
  token — rather than always on or always off.
  **Rationale**: the source's doc comment on `needsMemoization` gives both
  directions of the tradeoff concretely: without any cache, an adversarial
  pattern with several chained double-`*` segments re-derives the same
  failing search state through every combination of how much each
  segment consumed, with search time roughly doubling per added segment;
  with an unconditional cache, a `workspaceContains:` glob that is usually
  a bare filename with no backtracking at all (`package.json`,
  `.eslintrc`) still hashes and stores one dictionary entry per character
  of every path in a workspace scan, for a table that is written once and
  read never. The `> 1` threshold (rather than `>= 1`) is specifically
  because a single backtracking token already visits every state exactly
  once in a plain loop, so a cache adds pure overhead until a second such
  token exists — and a brace-group alternation counts as one backtracking
  token in that count, plus whatever its own branches contribute, or a
  pattern like `*.{js,ts,jsx,tsx,mjs,cjs}` (one leading `*`, one
  alternation) would sit at the threshold rather than past it and go
  uncached. This also means there is no hard timeout on matching even with
  memoization on — the cache bounds the work at
  `O(tokens.count * path.count)` states rather than exponential, but never
  imposes a ceiling on how large that product may be.
  **Approved**: pending
- **Decision**: `VSCodeEngineRange.isUnconstrained` is tested as an
  alternative to `minimumVersion >= 1.74.0`, rather than relying on
  `minimumVersion` alone, when deciding implicit command activation.
  **Rationale**: an engine of `"*"` parses to three zero bases with every
  must-equal flag cleared, which reads as a `minimumVersion` of 0.0.0 —
  indistinguishable, by `minimumVersion` alone, from a manifest that
  really did ask for the oldest possible VS Code. The source's own comment
  on `ActivationEventMatcher.init(manifest:)` states the consequence of
  getting this wrong: every `"vscode": "*"` manifest would fall below the
  floor and have its implicitly-activating commands mistakenly emptied,
  and the visible symptom would be a command-palette entry that silently
  does nothing rather than any error.
  **Approved**: pending
- **Decision**: `declaresWebviewPanel(viewType:)` is a distinct method from
  `matches(.webviewPanelRestored(viewType:))` and does not consult
  `activatesEagerly`.
  **Rationale**: the two questions are different — "does this extension
  wake for this trigger" (which an eager `"*"` answers yes to
  unconditionally) versus "does this extension claim ownership of this
  view type" (which an eager-only extension has not done). The source's
  doc comment states that conflating them would hand a restoring panel to
  an extension that merely activates eagerly, "a silent mis-delivery."
  **Approved**: pending
- **Decision**: `workspaceContains:` globs that use unsupported syntax
  (`[...]` character classes, a leading `!`, or a nested brace group) are
  rejected outright at parse time rather than approximated.
  **Rationale**: the source's doc comment on `GlobPattern.init` states
  that silently treating an unsupported character as a literal "would make
  a pattern match paths its author never intended it to." The rejected
  pattern is still surfaced, via `unsupportedPatterns`, so a report can
  name it rather than leave the author wondering why it never matched.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |

`separation-of-concerns` passes because the source splits the contract
across five single-purpose types rather than one monolith: `ActivationEvent`
only parses one manifest string, `WorkspaceScan` only prepares one scan's
paths for reuse, the file-local `GlobPattern` only matches a glob against a
decomposed path, and `ActivationEventMatcher` only orchestrates those three
plus the `contributes.commands` implicit-activation rule
(`parse-triage`, `glob-triage`, `implicit-activation-floor`, Overview).
`input-sanitization` passes because every `activationEvents` entry and
every `workspaceContains:` glob is third-party, extension-author-supplied
text that the parser validates against a fixed grammar rather than trusting:
an entry outside the seven recognized shapes is rejected
(`unrecognized-entry-rejection`), and a glob using an unsupported construct —
a `[...]` character class, a leading `!`, or a nested brace group — is
rejected rather than approximated as a literal, which the source's own doc
comment states is deliberate so an unsupported construct can never "match
paths its author never intended" (`glob-syntax-unsupported`).
`explicit-error-handling` passes because a failure to recognize or parse an
entry is never swallowed: it is always captured in a typed result the
caller can inspect — `unrecognizedEvents` for an entry `ActivationEvent`
could not parse, and `unsupportedPatterns` for a `workspaceContains:` glob
`GlobPattern` could not parse — rather than being silently dropped
(`parse-triage`, `glob-triage`).
`unit-test-coverage` passes: `ActivationEventMatcherTests.swift` exercises
parsing (every recognized shape, empty and empty-payload rejection,
whitespace trimming), matching (every `ActivationTrigger` case), implicit
activation (at, above and below the 1.74.0 floor, the unconstrained-`*`
case, and an unparseable engine), and the glob matcher (literal, `?`, `*`,
whole-segment `**`, brace alternation, and the rejected `[...]`/`!` shapes).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
