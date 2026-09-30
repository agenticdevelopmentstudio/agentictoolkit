<!-- leaf: implement-git-client/projects-project-filter--edge-cases · source: git-client-projects-project-filter.md -->

# ProjectFilter

**Rules** (cite as `implement-git-client/projects-project-filter--edge-cases#<slug>`):

- `null-and-empty-input` MUST — An empty query short-circuits both functions before either inspects text or repo — ranges(of:in:) returns [] and …
- `boundary-values` MUST — A query exactly as long as text, or longer than the remaining unsearched portion of text, causes …
- `concurrent-access` MUST — ProjectFilter declares no case, no stored property, and no static var; ranges(of:in:) and matches(_:query:) are pure …
- `cancellation-and-timeouts` MUST — Not applicable — every call to ranges(of:in:) and matches(_:query:) is synchronous and non-async; neither function …
- `concurrent-calls-with-different-arguments` MUST — Because both functions are pure and stateless, two callers invoking ranges(of:in:) or matches(_:query:) with different …

## Edge Cases

- **Null and empty input**: An empty `query` short-circuits both functions
  before either inspects `text` or `repo` — `ranges(of:in:)` returns `[]`
  and `matches(_:query:)` returns `true` (MUST, see
  `empty-query-yields-no-ranges`, `empty-query-matches-every-repo`,
  PF-001, PF-009). An empty `text` (or an empty `repo.name`/`repo.path`)
  makes the scan loop's initial condition false, so `ranges(of:in:)`
  returns `[]` for any non-empty query (MUST, see
  `empty-text-yields-no-ranges`).
- **Boundary values**: A `query` exactly as long as `text`, or longer than
  the remaining unsearched portion of `text`, causes
  `haystack.range(of:options:range:)` to return `NSNotFound`, which the
  `guard match.location != NSNotFound else { break }` catches, ending the
  scan with whatever ranges were already found (MUST). A `query` that
  overlaps itself when repeated in `text` (e.g. `"aa"` in `"aaa"`) is
  under-counted by design, not by accident — see
  `non-overlapping-scan-advance` and PF-010 (MUST).
- **Concurrent access**: `ProjectFilter` declares no case, no stored
  property, and no `static var`; `ranges(of:in:)` and `matches(_:query:)`
  are pure functions over their `String`/`GitRepo` arguments, and the
  `NSString` each call bridges via `text as NSString` is a fresh, immutable
  value local to that call. Concurrent calls from any thread or isolation
  domain MUST be safe with no additional synchronization required (MUST,
  see `stateless-and-pure`).
- **Error states**: Not applicable — no function in `ProjectFilter.swift`
  throws, returns an `Optional` that the caller must unwrap, or calls
  anything that can fail; the one failure signal in the source,
  `NSNotFound`, is checked with a `guard` and turned into a normal loop
  exit, never surfaced to the caller as an error.
- **Offline or disconnected state**: Not applicable — `ProjectFilter.swift`
  performs no network call and depends on no connectivity; it operates only
  on in-memory `String` values already held by the caller.
- **Missing file or unreachable server**: Not applicable — `ProjectFilter.swift`
  performs no file-system or network I/O of its own; `repo.path` is a
  string it compares textually, never a path it opens, stats, or reads.
- **Cancellation and timeouts**: Not applicable — every call to
  `ranges(of:in:)` and `matches(_:query:)` is synchronous and non-`async`;
  neither function spawns a subprocess or a long-running operation that
  something else could cancel or that could time out (MUST, see
  `ranges-loop-terminates` for the source's own bound on how long a single
  call can run).
- **Concurrent calls with different arguments**: Because both functions are
  pure and stateless, two callers invoking `ranges(of:in:)` or
  `matches(_:query:)` with different `query`/`text`/`repo` arguments at the
  same time on different threads MUST each observe only their own inputs
  and outputs, with no cross-talk between the two calls (MUST, see
  `stateless-and-pure`).
