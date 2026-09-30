<!-- leaf: implement-extension-host-core-1/extensions-activation-event-matcher--part-2 · source: extension-host-core-extensions-activation-event-matcher.md -->

# ActivationEventMatcher — continued (part 2)

**Rules** (cite as `implement-extension-host-core-1/extensions-activation-event-matcher--part-2#<slug>`):

- `event-kind-cases` MUST
- `event-value-semantics` MUST
- `raw-value-preservation` MUST
- `whitespace-trimming` MUST
- `entry-parsing-order` MUST
- `empty-entry-rejection` MUST
- `prefixed-payload-extraction` MUST
- `empty-payload-rejection` MUST
- `unrecognized-entry-rejection` MUST
- `matcher-value-semantics` MUST
- `parse-triage` MUST
- `eager-activation-flag` MUST
- `glob-triage` MUST
- `glob-syntax-supported` MUST
- `glob-syntax-unsupported` MUST
- `glob-anchoring` MUST
- `glob-character-granularity` MUST
- `workspace-scan-decomposition` MUST
- `workspace-scan-equality` MUST
- `workspace-scan-reuse` MUST
- `implicit-activation-floor` MUST
- `implicit-activation-unparseable-engine` MUST
- `command-match` MUST
- `document-opened-match` MUST
- `startup-match` MUST
- `webview-panel-restored-match` MUST
- `view-shown-match` MUST
- `workspace-scanned-match` MUST
- `eager-short-circuit` MUST
- `webview-panel-ownership-exclusion` MUST
- `empty-manifest-no-match` MUST
- `backtracking-memoization` SHOULD

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
