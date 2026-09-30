<!-- leaf: implement-extension-host-core-1/extensions-activation-event-matcher--part-4 · source: extension-host-core-extensions-activation-event-matcher.md -->

# ActivationEventMatcher — continued (part 4)

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
