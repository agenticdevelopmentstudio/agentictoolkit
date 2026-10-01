---
id: a29c23d4-a086-4413-9843-6b319e340646
title: Activation Event Matcher
domain: agentictoolkit://cookbook/workspace/extensions/manifest/activation-event-matcher
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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

# Activation Event Matcher

## Overview

The activation event matcher is the parser and query engine for a VS Code
extension manifest's `activationEvents` array. It exists so a host does not
re-parse the same five prefixes at every call site. Together with its
supporting concepts it is the whole activation-matching contract: an
activation event parses one manifest entry into a typed kind; an activation
trigger names a thing that just happened in the host (startup finished, a
document opened, a command invoked, a webview panel restored, a
contributed view shown, or a workspace scan completed); a workspace scan is
one directory walk's paths, decomposed once for reuse across every
extension checked against it; a glob pattern is a backtracking matcher for
`workspaceContains:` globs; and the activation event matcher itself, built
once per installed extension from its manifest, answers whether it matches
any given activation trigger and also implements VS Code 1.74's "implicit
activation from `contributes.commands`" rule. The extension host installer
is the sole production caller today: it builds one matcher per extension
host installation at construction and queries it repeatedly as startup,
document-open, command-invocation, view-shown and workspace-scan triggers
occur.

## Behavioral Requirements

- **event-kind-cases**: An activation event's kind MUST expose exactly
  seven kinds: any (`"*"`), startup finished (`"onStartupFinished"`),
  language (`"onLanguage:swift"` → the language id, e.g. `"swift"`), command
  (`"onCommand:foo.bar"` → the command id, e.g. `"foo.bar"`),
  workspace-contains (`"workspaceContains:**/*.csproj"` → the glob), webview
  panel (`"onWebviewPanel:markdown.preview"` → the view type), and view
  (`"onView:package-explorer"` → the view id).
- **event-value-semantics**: An activation event and an activation trigger
  MUST be immutable, comparable values usable safely from any thread; an
  event's kind MUST also be an immutable, comparable value.
- **raw-value-preservation**: An activation event's raw text MUST hold the
  entry exactly as the manifest spelled it — including any leading or
  trailing whitespace — even though recognition of the entry's shape
  operates on a trimmed copy; this is so a diagnostic can quote what the
  author wrote.
- **whitespace-trimming**: Parsing an activation event MUST trim leading
  and trailing whitespace before recognizing the entry's shape.
- **entry-parsing-order**: Parsing MUST test the trimmed value, in order,
  against: empty (fails), exactly `"*"`, exactly `"onStartupFinished"`,
  then the prefixes `"onLanguage:"`, `"onCommand:"`, `"workspaceContains:"`,
  `"onWebviewPanel:"`, `"onView:"`; the first match wins.
- **empty-entry-rejection**: An entry that trims to the empty string MUST
  fail to parse.
- **prefixed-payload-extraction**: For each of the five colon-prefixed
  forms, the payload MUST be everything after the prefix, taken verbatim
  and never case-normalized — VS Code language and command ids are
  lowercase by convention but the editor never enforces it, so normalizing
  here would accept manifests VS Code itself would not activate.
- **empty-payload-rejection**: A prefixed entry whose payload is empty
  after the colon (for example `"onLanguage:"`) MUST fail to parse rather
  than being read as a match against the empty string.
- **unrecognized-entry-rejection**: A trimmed value matching none of the
  seven recognized shapes MUST fail to parse.
- **matcher-value-semantics**: The activation event matcher MUST be an
  immutable, comparable value usable safely from any thread.
- **parse-triage**: Building the matcher from a manifest MUST parse every
  entry of `activationEvents`, in order, placing every entry that parses
  into the recognized-events list (in original manifest order) and the
  raw, untrimmed text of every entry that fails to parse into the
  unrecognized-entries list (in original manifest order); an unrecognized
  entry MUST NOT be dropped silently.
- **eager-activation-flag**: Eager activation MUST be true if and only if
  the recognized-events list contains an entry whose kind is any.
- **glob-triage**: For every parsed workspace-contains event, in order,
  building the matcher MUST attempt to build a glob pattern from the glob
  text; a glob that parses MUST be added to the matcher's internal pattern
  list (used to answer workspace-scan triggers), and a glob that fails to
  parse MUST have its raw payload text (not the `"workspaceContains:"`
  prefix) appended to the unsupported-patterns list, in order; a pattern in
  the unsupported-patterns list MUST NOT ever match.
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
  negation, MUST fail to parse rather than being approximated as a literal
  or a partial match; treating an unsupported construct as a literal
  "would make a pattern match paths its author never intended."
- **glob-anchoring**: A parsed glob pattern MUST match a path only when the
  pattern consumes the whole path at both ends; a partial or substring
  match MUST NOT count as a match.
- **glob-character-granularity**: Glob matching MUST operate over whole
  displayed characters (grapheme clusters) of both the pattern and the
  path, never raw code points or code units, so a multi-scalar character is
  compared as one unit on either side of the match (Platform Notes: SwiftUI
  and Design Decisions — the granularity is not guaranteed to be identical
  across every platform's implementation).
- **workspace-scan-decomposition**: Building a workspace scan MUST
  decompose every relative path into its character sequence exactly once,
  at construction, storing the result at the matching index; this
  decomposition MUST NOT be repeated per pattern or per extension checked
  against the same scan.
- **workspace-scan-equality**: Two workspace scans MUST be equal if and
  only if their relative-paths lists are equal; the decomposed-paths index
  (a derived value) MUST NOT participate in equality.
- **workspace-scan-reuse**: A caller that checks more than one matcher
  against the same directory walk MUST construct one shared workspace scan
  and pass it to every workspace-scan check, rather than building a fresh
  workspace scan per extension; the cost of not doing so is concrete (a
  20,000-path workspace with 30 installed extensions redundantly
  decomposing 600,000 paths for input that never changed between calls).
- **implicit-activation-floor**: The implicitly activating commands MUST
  equal the set of `contributes.commands` command-id strings when the
  manifest's `engines.vscode` parses into an engine range that is either
  unconstrained (for example `"*"`) or whose minimum version is greater
  than or equal to 1.74.0; otherwise the implicitly activating commands
  MUST be empty. The version tested is the manifest's own declared engine,
  never the host's, because an extension that still targets an older VS
  Code cannot rely on behavior its stated minimum predates.
- **implicit-activation-unparseable-engine**: A manifest whose
  `engines.vscode` does not parse into an engine range MUST yield an empty
  implicitly-activating-commands set; an engine string this component
  cannot evaluate MUST NOT be treated as evidence the extension supports
  the newer inference.
- **command-match**: Matching a command-invoked trigger MUST return true
  if and only if the command id is a member of the implicitly activating
  commands, or the recognized-events list contains an entry whose kind is
  command with that same id (exact, case-sensitive match); otherwise it
  MUST return false.
- **document-opened-match**: Matching a document-opened trigger MUST return
  true if and only if the recognized-events list contains an entry whose
  kind is language with a language id exactly equal (case-sensitive) to the
  trigger's language id.
- **startup-match**: Matching the startup-finished trigger MUST return true
  if and only if the recognized-events list contains an entry whose kind is
  startup finished.
- **webview-panel-restored-match**: Matching a webview-panel-restored
  trigger MUST return true if and only if the recognized-events list
  contains an entry whose kind is webview panel with a view type exactly
  equal (case-sensitive) to the trigger's view type.
- **view-shown-match**: Matching a view-shown trigger MUST return true if
  and only if the recognized-events list contains an entry whose kind is
  view with a view id exactly equal (case-sensitive) to the trigger's view
  id.
- **workspace-scanned-match**: Matching a workspace-scanned trigger MUST
  return false immediately when the matcher's parsed workspace-contains
  pattern list is empty; otherwise it MUST return true if and only if at
  least one of the scan's decomposed paths matches at least one parsed
  pattern.
- **eager-short-circuit**: When eager activation is true, matching MUST
  return true for every activation trigger without evaluating any other
  rule.
- **webview-panel-ownership-exclusion**: Declaring ownership of a webview
  panel view type MUST NOT consult eager activation; it MUST return true if
  and only if the recognized-events list contains a webview-panel entry
  with that exact (case-sensitive) view type, regardless of whether the
  manifest also declares `"*"`. The reason: activating eagerly answers
  "does this wake the extension," while owning a view type answers "whose
  panel is this" — and an extension that only activates eagerly has made no
  claim on any view type, so handing it someone else's panel would be a
  silent mis-delivery.
- **empty-manifest-no-match**: A matcher built from a manifest with no
  `activationEvents` entries and no implicitly activating commands MUST
  have eager activation false, and matching MUST return false for every
  activation trigger; an extension with no recognized events and no
  implicitly activating commands MUST NOT fall back to eager activation.
- **backtracking-memoization**: Matching a glob pattern SHOULD memoize
  search state — on the pair of token index and path index for the
  pattern's own tokens, and on the triple of branch id, branch-internal
  index and path index for each brace-group branch — whenever the pattern
  contains more than one token capable of consuming a variable amount of
  the path (a lone `*`, a whole-segment double-`*`, or a brace-group
  alternation, each alternation counted together with its own contained
  tokens); a pattern with at most one such token MAY skip memoization,
  since every search state is then reached exactly once regardless. See
  Design Decisions for the rationale.
- **single-matcher-trigger-factory**: A convenience for building a
  workspace-scanned trigger directly from a list of relative paths MAY be
  used by a caller that has exactly one matcher to ask (a test, or a replay
  for a single extension with no prepared scan to hand); the
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
| aem-001 | event-kind-cases, glob-triage | Parse the activation event text `"*"`. | kind is any; raw text is `"*"`. |
| aem-002 | entry-parsing-order | Parse the activation event text `"onStartupFinished"`. | kind is startup finished. |
| aem-003 | prefixed-payload-extraction | Parse the activation event text `"onLanguage:swift"`. | kind is language, with language id `"swift"`. |
| aem-004 | prefixed-payload-extraction | Parse the activation event text `"onCommand:foo.bar"`. | kind is command, with command id `"foo.bar"`. |
| aem-005 | prefixed-payload-extraction | Parse the activation event text `"onWebviewPanel:markdown.preview"`. | kind is webview panel, with view type `"markdown.preview"`. |
| aem-006 | empty-payload-rejection | Parse the activation event texts `"onLanguage:"`, `"onCommand:"`, `"workspaceContains:"`, `"onWebviewPanel:"`, `"onView:"`. | Each fails to parse. |
| aem-007 | empty-entry-rejection, unrecognized-entry-rejection | Parse the activation event texts `""`, `"   "`, `"onDebug"`. | Each fails to parse. |
| aem-008 | whitespace-trimming | Parse the activation event text `"  onStartupFinished  "`. | kind is startup finished; raw text is `"  onStartupFinished  "` (unchanged). |
| aem-009 | parse-triage, eager-activation-flag | Build a matcher from a manifest with `activationEvents: ["onStartupFinished", "onDebug", "onLanguage:swift"]`. | The recognized-events list holds the two recognized entries in order; the unrecognized-entries list is `["onDebug"]`; eager activation is false. |
| aem-010 | eager-activation-flag, eager-short-circuit | Build a matcher from a manifest with `activationEvents: ["*"]`. | Eager activation is true; the startup-finished trigger, a document-opened trigger for language id `"swift"`, a command-invoked trigger for `"anything"`, and a workspace-scanned trigger against an empty scan all match. |
| aem-011 | startup-match | Build a matcher from a manifest with `activationEvents: ["onStartupFinished"]`. | The startup-finished trigger matches; a document-opened trigger for language id `"swift"` does not. |
| aem-012 | document-opened-match | Build a matcher from a manifest with `activationEvents: ["onLanguage:swift"]`. | A document-opened trigger for language id `"swift"` matches; for language id `"Swift"` it does not (case-sensitive). |
| aem-013 | command-match | Build a matcher from a manifest with `activationEvents: ["onCommand:a.b"]`. | A command-invoked trigger for `"a.b"` matches; for `"a"` it does not. |
| aem-014 | empty-manifest-no-match | Build a matcher from a manifest with an empty `activationEvents` and no `contributes.commands`. | Eager activation is false; no trigger matches — not the startup-finished trigger, a document-opened trigger for language id `"swift"`, a command-invoked trigger for `"x"`, nor a workspace-scanned trigger against a scan with one relative path. |
| aem-015 | implicit-activation-floor, command-match | Build a matcher from a manifest with `engines.vscode: "^1.74.0"`, `contributes.commands: [{command: "x.run", ...}]`, and no `onCommand:` entry. | The implicitly activating commands are `["x.run"]`; a command-invoked trigger for `"x.run"` matches. |
| aem-016 | implicit-activation-floor | The same manifest with `engines.vscode: "^1.73.0"`. | The implicitly activating commands are empty; a command-invoked trigger for `"x.run"` does not match. |
| aem-017 | implicit-activation-floor | The same manifest with `engines.vscode: "*"`. | The implicitly activating commands are `["x.run"]` (an unconstrained engine takes the same branch as a modern floor — an unconstrained engine is not the same as a declared minimum of 0.0.0). |
| aem-018 | implicit-activation-unparseable-engine | The same manifest with `engines.vscode: "~1.74.0"` (a shape the engine range cannot parse). | The implicitly activating commands are empty; a command-invoked trigger for `"x.run"` does not match. |
| aem-019 | command-match | Build a matcher from a manifest with `engines.vscode: "^1.60.0"`, `activationEvents: ["onCommand:x.run"]`, `contributes.commands: [{command: "x.run", ...}]`. | The implicitly activating commands are empty, yet a command-invoked trigger for `"x.run"` matches (the explicit `onCommand:` entry matches independently of the implicit-activation floor). |
| aem-020 | glob-syntax-supported, glob-anchoring | Match the glob `"*.csproj"` against the path `"a.csproj"`, then against `"src/a.csproj"`. | Matches the first; does not match the second (a single `*` never crosses a path separator). |
| aem-021 | glob-syntax-supported | Match a glob with a leading whole-segment double-`*` followed by a separator, then `*.csproj`, against the path `"a.csproj"`, then against a deeply nested path ending in `.csproj`. | Matches both (the whole-segment double-`*` crosses separators). |
| aem-022 | glob-syntax-supported | Match the glob `"?.txt"` against `"a.txt"`, then against `"ab.txt"`. | Matches the first; does not match the second. |
| aem-023 | glob-syntax-supported | Match a brace group of two comma-separated alternatives (for example `package.json` or `bower.json`) against each alternative's exact filename, then against an unrelated filename. | Matches both alternatives; does not match the unrelated filename. |
| aem-024 | glob-syntax-unsupported | Build the glob pattern `"[abc].txt"`. | Building it fails; the raw text `"[abc].txt"` is appended to the unsupported-patterns list; it never matches a workspace-scanned trigger. |
| aem-025 | glob-syntax-unsupported | Build a glob pattern beginning with `"!"`. | Building it fails; the raw text is appended to the unsupported-patterns list. |
| aem-026 | glob-anchoring | Match the glob `"a.txt"` against the path `"axtxt"`. | Does not match (no substring match). |
| aem-027 | workspace-scanned-match | Match a pattern that parses against a workspace scan built from an empty list of relative paths. | The workspace-scanned trigger does not match. |
| aem-028 | backtracking-memoization | Match an adversarial pattern with several whole-segment double-`*` tokens separated by literal `a` characters and ending in a literal `b`, against a long run of `a` characters with no trailing `b`. | Resolves to no match without an exponential increase in search time as more double-`*` segments are added. |
| aem-029 | webview-panel-restored-match | Build a matcher from a manifest with `activationEvents: ["onWebviewPanel:markdown.preview"]`. | A webview-panel-restored trigger for view type `"markdown.preview"` matches; for `"markdown.other"` it does not. |
| aem-030 | webview-panel-ownership-exclusion | Build a matcher from a manifest with `activationEvents: ["*"]`. | A webview-panel-restored trigger for view type `"markdown.preview"` matches, but declaring ownership of that view type does not. |
| aem-031 | webview-panel-ownership-exclusion | Build a matcher from a manifest with `activationEvents: ["onStartupFinished", "onWebviewPanel:markdown.preview"]`. | Declaring ownership of view type `"markdown.preview"` is true; of `"markdown.Preview"` is false (case-sensitive); of `""` is false. |
| aem-032 | view-shown-match | Build a matcher from a manifest with `activationEvents: ["onView:explorer"]`. | A view-shown trigger for view id `"explorer"` matches; for `"other"` it does not. Not directly asserted by a dedicated test for this exact trigger — traced to the matcher's handling of the view-shown case, which follows the same pattern as the tested webview-panel-restored case. |

## Edge Cases

- **Null/empty input**: an empty `activationEvents` array, or one containing
  only entries that fail to parse, yields an empty recognized-events list,
  eager activation false, and (per `empty-manifest-no-match`) no trigger
  matches. An entry that trims to the empty string, or a prefixed entry
  with an empty payload, is rejected rather than treated as a wildcard or
  an empty-string match (`empty-entry-rejection`, `empty-payload-rejection`).
- **Malformed glob syntax**: a `workspaceContains:` glob using a
  square-bracket character class or a leading exclamation-mark negation is
  rejected at parse time and recorded in the unsupported-patterns list; it
  never matches, and it never causes building the matcher to fail or throw
  (`glob-syntax-unsupported`, `glob-triage`).
- **Malformed engine range**: an `engines.vscode` string this component
  cannot parse (anything outside `*`, an optional `^`/`>=` prefix, and
  three numeric-or-`x` components) yields an empty implicitly-activating-
  commands set, never a crash or a missing matcher
  (`implicit-activation-unparseable-engine`).
- **Boundary values — implicit-activation floor**: an engine of exactly
  `"1.74.0"` or `"^1.74.0"` grants implicit activation; an engine one patch
  below the floor (`"^1.73.0"`, or any range whose minimum version is less
  than 1.74.0) does not; an unconstrained engine (`"*"`) grants it, because
  "no version claim" is treated as distinct from "a claim to predate 1.74"
  (`implicit-activation-floor`).
- **Boundary values — glob anchoring**: a pattern must consume the entire
  path at both ends; a pattern that matches a prefix or suffix of a path
  but not the whole of it does not match (`glob-anchoring`).
- **Concurrent access**: an activation event, an activation trigger, a
  workspace scan, and the activation event matcher are all immutable
  values with no mutable stored state reachable after construction, and
  glob matching builds its memoization tables as local state scoped to
  that one call rather than shared mutable state on the pattern — so
  matching MAY be called concurrently against the same matcher or the same
  glob pattern, with no synchronization required.
- **Error states**: not applicable — every operation in this component is a
  synchronous, non-throwing, pure computation over already-in-memory
  values; there is no I/O, so there is no error channel to define.
- **Offline/disconnected**: not applicable — this component performs no
  networking and touches no filesystem; a workspace scan's paths are
  supplied by the caller, who is responsible for the directory walk that
  produced them.
- **Unbounded input size**: checking a workspace-scanned trigger and
  matching a glob pattern define no timeout, cancellation, or size limit;
  matching runs synchronously to completion regardless of how many paths a
  workspace scan carries or how many backtracking tokens a pattern contains
  (mitigated for cost, not bounded for time, by `backtracking-memoization`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| manifest | extension manifest | none (required) | Supplies `activationEvents`, `engines.vscode`, and `contributes.commands` to the matcher's construction; there is no default manifest. |
| trigger | activation trigger | none (required) | The event the matcher is asked to check; one of: startup finished, document opened (with a language id), command invoked (with a command id), webview panel restored (with a view type), view shown (with a view id), workspace scanned (with a scan). |
| relativePaths | list of strings | none (required, when building a workspace scan) | Workspace-relative paths, `/`-separated with no leading slash, that a caller's directory walk produced; supplied once per scan when building a workspace scan, or via the single-matcher convenience factory. |

There are no environment variables, settings keys, or injected dependencies:
the activation event matcher and its supporting concepts take every input
as a plain argument and read no ambient state.

## Deep Linking

Not applicable: this component parses and matches manifest strings in
memory; it defines no URL scheme, route, or navigable destination.

## Localization

Not applicable: this component produces no user-facing strings. It carries
manifest text (the unrecognized entries, the unsupported patterns, language
and command ids) verbatim for a caller to report, but formats or localizes
none of it itself.

## Accessibility Options

Not applicable: this component has no visual or interactive surface for a
system accessibility display option to affect.

## Feature Flags

Not applicable: this component defines no feature flag, build
configuration check, or remote-config lookup; its behavior is fixed by the
manifest it is constructed with.

## Analytics

Not applicable: this component emits no analytics events; it returns
values to its caller and performs no telemetry of its own.

## Privacy

- **Data collected**: none. The matcher reads only the `activationEvents`,
  `engines.vscode`, and `contributes.commands` fields of a caller-supplied
  extension manifest, and the relative paths of a caller-supplied
  workspace scan; none of this is device- or user-identifying data, and the
  component collects nothing beyond what its caller already handed it.
- **Storage**: none. Every value is held only in the in-memory matcher or
  workspace-scan instance for the duration the caller keeps it; nothing is
  written to disk by this component.
- **Transmission**: none. This component performs no networking.
- **Retention**: for the lifetime of the matcher or workspace-scan value
  the caller holds; releasing the value releases the data with it.

## Logging

Not applicable: this component contains no logging call. Entries it cannot
recognize or match (the unrecognized entries, the unsupported patterns) are
surfaced as plain data for a caller to log or report, rather than being
logged by this component itself.

## Platform Notes

- **SwiftUI**: the source (`ActivationEventMatcher.swift`,
  `ExtensionManifest.swift`, `VSCodeEngineRange.swift`,
  `SemanticVersion.swift`) is plain Foundation logic — value types, string
  parsing, and a hand-rolled backtracking matcher — with no dependency on
  SwiftUI or any view-layer framework. `ActivationEvent`, `ActivationTrigger`,
  `ActivationEvent.Kind`, `WorkspaceScan`, and `ActivationEventMatcher` are
  declared `Sendable` and `Equatable`; whitespace trimming uses Foundation's
  `.whitespaces` character set. Glob matching operates over Swift
  `Character` (extended grapheme cluster) elements of both pattern and path
  (see Design Decisions). A port that keeps this component in Swift needs
  nothing beyond `Foundation`.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/ActivationEventMatcher.swift` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/manifest/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
