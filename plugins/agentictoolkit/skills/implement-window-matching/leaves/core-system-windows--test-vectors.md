<!-- leaf: implement-window-matching/core-system-windows--test-vectors · source: window-matching-core-system-windows.md -->

# Window Matching Core System Windows

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wmcsw-001 | strategy-cases, strategy-case-iterable | `MatchStrategy.allCases` | `[.appAndTitleExact, .appAndTitleSubstring, .appAndTitleRegex, .appOnly]`, count 4 |
| wmcsw-002 | strategy-raw-values | JSON-encode `MatchStrategy.appOnly`; decode `"appAndTitleRegex"` | `"appOnly"`; `.appAndTitleRegex` |
| wmcsw-003 | strategy-unknown-raw | Decode the JSON string `"fuzzy"` as `MatchStrategy`; `MatchStrategy(rawValue: "fuzzy")` | Throws `DecodingError.dataCorrupted`; `nil` |
| wmcsw-004 | display-name-exact, display-name-substring, display-name-regex, display-name-app-only | `displayName` of each case in declaration order | `"Exact"`, `"Substring"`, `"Regex"`, `"App Only"` |
| wmcsw-005 | fingerprint-init-verbatim, fingerprint-fields | `SystemWindowFingerprint(app: "Xcode", titlePattern: " Proj ", matchStrategy: .appAndTitleExact, display: 2)` | `app == "Xcode"`, `titlePattern == " Proj "` (untrimmed), `matchStrategy == .appAndTitleExact`, `display == 2` |
| wmcsw-006 | regex-not-validated, strategy-semantics-declared | Fingerprint with `titlePattern: "JIRA-\\d+"`, `.appAndTitleRegex`; score against window app `"TestApp"`, title `"JIRA-1234 details"`, different display | Fingerprint constructs; `SystemWindowMatcher().score` returns 80 (`SystemWindowMatcherTests.regexFamily`) |
| wmcsw-007 | regex-not-validated | Fingerprint with `titlePattern: "("`, `.appAndTitleRegex` | Fingerprint constructs without error; the matcher scores it 0 and logs the compile error |
| wmcsw-008 | display-tie-breaker | Fingerprint `.appOnly`, app `"Terminal"`, `display: 7`; window app `"Terminal"`, `display: 7` | `SystemWindowMatcher().score` returns 90 (80 + 10 display bonus) (`SystemWindowMatcherTests.displayBonus`) |
| wmcsw-009 | with-title-copy, with-title-non-mutating | `info = SystemWindowInfo(id: 5, app: "Mail", pid: 42, title: "", frame: CGRect(x: 1, y: 2, width: 3, height: 4), display: 1, isOnScreen: true, layer: 0)`; `copy = info.withTitle("Inbox")` | `copy.title == "Inbox"`; `copy.id == 5`, `pid == 42`, `frame`, `display`, `isOnScreen`, `layer` equal `info`'s; `info.title == ""` |
| wmcsw-010 | info-identifiable, equatable | `info` and `info.withTitle("x")` from wmcsw-009 | Same `id`; `info == info.withTitle("x")` is `false` |
| wmcsw-011 | snapshot-id-default, snapshot-window-id-default, snapshot-is-live | `SystemWindowSnapshot(fingerprint: fp, savedFrame: .zero, display: 0, app: "Mail", title: "")` twice | Two different `id` values; `windowID == nil`; `isLive == false` |
| wmcsw-012 | snapshot-is-live | Snapshot with `windowID: 9`; then set `windowID = nil` | `isLive == true`, then `false` |
| wmcsw-013 | snapshot-display-independent | Snapshot with `fingerprint.display == 1`, `display: 1`; set `display = 3` | `display == 3`; `fingerprint.display == 1` |
| wmcsw-014 | context-init-defaults | `SystemWindowContext(name: "Docs")` | `color == "#007AFF"`, `windowSnapshots.isEmpty`, `lastFocusedWindowID == nil`, `createdAt` within 1 s of now, non-nil `id` |
| wmcsw-015 | add-window-append | Empty context; `addWindow(a)`, `addWindow(b)` (distinct `id`s) | `windowSnapshots.map(\.id) == [a.id, b.id]` |
| wmcsw-016 | add-window-replace, add-window-keeps-focus | Context `[a, b]`, `lastFocusedWindowID = a.id`; `addWindow(a')` where `a'.id == a.id`, `a'.title == "new"` | Count 2, order `[a', b]`, `windowSnapshots[0].title == "new"`, `lastFocusedWindowID == a.id` |
| wmcsw-017 | add-window-no-window-id-dedupe | Empty context; add `a` and `b` with distinct `id`s, both `windowID: 7` | Count 2 |
| wmcsw-018 | remove-by-id, remove-by-id-clears-focus | Context `[a, b]`, `lastFocusedWindowID = a.id`; `removeWindow(id: a.id)` | Returns `a`; `windowSnapshots == [b]`; `lastFocusedWindowID == nil` |
| wmcsw-019 | remove-by-id-missing | Context `[a]`, `lastFocusedWindowID = a.id`; `removeWindow(id: UUID())` | Returns `nil`; context unchanged |
| wmcsw-020 | remove-by-id-clears-focus | Context `[a, b]`, `lastFocusedWindowID = b.id`; `removeWindow(id: a.id)` | `lastFocusedWindowID == b.id` |
| wmcsw-021 | remove-by-window-id, remove-by-window-id-clears-focus | Context `[a (windowID 7), b (windowID 7)]`, `lastFocusedWindowID = a.id`; `removeWindow(windowID: 7)` | Returns `a`; `windowSnapshots == [b]`; `lastFocusedWindowID == nil` |
| wmcsw-022 | remove-by-window-id-missing | Context `[a (windowID nil)]`; `removeWindow(windowID: 0)` | Returns `nil`; context unchanged |
| wmcsw-023 | snapshot-lookup | Context `[a, b]`; `snapshot(id: b.id)`; `snapshot(id: UUID())` | `b`; `nil` |
| wmcsw-024 | update-by-id, update-scope | Context `[a]`; `updateSnapshot(id: a.id) { $0.title = "T"; $0.windowID = 3 }` | Returns `true`; `windowSnapshots[0].title == "T"`, `windowID == 3`, `id == a.id` |
| wmcsw-025 | update-by-id-missing | Context `[a]`; `updateSnapshot(id: UUID()) { _ in called = true }` | Returns `false`; `called == false` |
| wmcsw-026 | update-by-window-id | Context `[a (windowID 4)]`; `updateSnapshot(windowID: 4) { $0.savedFrame = CGRect(x: 0, y: 0, width: 10, height: 10) }`; then `updateSnapshot(windowID: 5) { _ in }` | `true` and frame updated; then `false` |
| wmcsw-027 | live-window-count | Context with snapshots whose `windowID`s are `1`, `nil`, `2` | `liveWindowCount == 2` |
| wmcsw-028 | codable, optional-omitted, computed-not-encoded | Encode a snapshot with `windowID == nil` using a `.sortedKeys` `JSONEncoder` | Keys are `app`, `display`, `fingerprint`, `id`, `lastSeen`, `savedFrame`, `title`; no `windowID` and no `isLive` key |
| wmcsw-029 | frame-encoding | Encode `SystemWindowInfo` with `frame: CGRect(x: 1, y: 2, width: 3, height: 4)` | `"frame":[[1,2],[3,4]]` |
| wmcsw-030 | missing-key-throws | Decode `SystemWindowFingerprint` from `{"app":"Xcode","titlePattern":"P","matchStrategy":"appOnly"}` | Throws `DecodingError.keyNotFound` for `display` |
| wmcsw-031 | codable, equatable | Encode then decode a `SystemWindowContext` with two snapshots using the same date strategy both ways | Decoded value `==` original (dates at a precision the strategy preserves) |
| wmcsw-032 | no-side-effects, no-errors | Call every public member of the five types | None throws; no file, network, log or process activity |
