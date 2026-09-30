<!-- leaf: implement-window-matching/heuristics--edge-cases · source: window-matching-heuristics.md -->

# Window Matching Heuristics

**Rules** (cite as `implement-window-matching/heuristics--edge-cases#<slug>`):

- `empty-title` MUST — every built-in returns nil for "" before doing any parsing (MUST; empty-title-nil).
- `whitespace-only-title` MUST — Xcode, Brave, VS Code and Terminal trim to empty and return nil; Warp returns nil because there is no " - " (MUST).
- `title-with-newlines` MUST — trimming uses spaces and tabs only, so a leading or trailing newline stays in the returned pattern (MUST; …
- `both-em-and-en-dash-present` MUST — only the em dash splits; en-dash text stays inside a component (MUST; separator-first-match-wins).
- `en-dash-inside-content` MUST — a title whose content contains " – " (for example a folder named "App – Prod") with no em dash is split there; …
- `empty-components-from-a-leading-or-trailing-separator` MUST — components are kept in place, empty; Xcode, VS Code and Terminal return nil when the component they select is empty …
- `warp-title-with-no` MUST — returns nil, with no whole-title fallback (MUST; warp-requires-hyphen-separator).
- `warp-root-or-slash-only-path` MUST — "/" or "//" yields nil (MUST; warp-root-path-nil).
- `warp-dirty-indicator-without-a-leading-space` MUST — "a - proj*" keeps the "*" ("proj*"), because only the two-character " *" suffix is stripped (MUST).
- `warp-parenthesis-without-a-leading-space` MUST — "a - proj(main)" keeps "proj(main)", because only " (" cuts the branch (MUST).
- `brave-suffix-variants` MUST — " - brave" (lowercase) or " - Brave Browser" do not strip; the whole trimmed title is returned (MUST; …
- `vs-code-generic-title-in-the-first-position` MUST — "Welcome — Visual Studio Code" returns "Welcome" (MUST, as the code behaves); the doc comment claims nil — the open …
- `vs-code-generic-comparison-case` MUST — "welcome" (lowercase) is not generic and is returned as-is (MUST).
- `vs-code-dotted-names-that-are-not-filenames` MUST — "v1.2 — proj" returns "v1.2" because "2" is not a listed extension; ".json" alone is one piece after dropping the empty …
- `vs-code-both-first-and-last-look-like-filenames` MUST — the first component is returned (MUST; vscode-default-first).
- `terminal-double-dash` MUST — only one leading "-" is removed (MUST; terminal-strip-one-dash).
- `terminal-dimensions-only` MUST — "u — 80x24" returns "80x24" as the command, since the second component is taken blindly (MUST).
- `concurrent-access` MUST — all five heuristics are stateless Sendable structs with pure functions; concurrent calls cannot interleave on shared …

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
