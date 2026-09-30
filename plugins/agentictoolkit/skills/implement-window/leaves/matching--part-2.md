<!-- leaf: implement-window/matching--part-2 · source: window-matching.md -->

# Window Matching — continued (part 2)

**Rules** (cite as `implement-window/matching--part-2#<slug>`):

- `registry-built-ins` MUST
- `registry-shared` MUST
- `registry-init` MUST
- `registry-case-insensitive` MUST
- `registry-last-wins` MUST
- `registry-register` MUST
- `registry-custom-replace` MUST
- `registry-custom-overrides` MUST
- `registry-custom-clear` MUST
- `registry-is-built-in` MUST
- `registry-snapshots` MUST
- `registry-thread-safety` MUST
- `registry-no-cross-call-snapshot` MUST
- `matcher-registry` MUST
- `fingerprint-heuristic` MUST
- `fingerprint-fallback` MUST
- `fingerprint-empty-title` MUST
- `fingerprint-app-display` MUST
- `fingerprint-never-exact` MUST
- `score-app-gate` MUST
- `score-live-pattern` MUST
- `score-exact` MUST
- `score-substring-equal` MUST
- `score-substring-contains` MUST
- `score-substring-direction` MUST
- `score-substring-miss` MUST
- `score-regex` MUST
- `score-regex-invalid` MUST
- `score-app-only` MUST
- `score-display-bonus` MUST
- `score-range` MUST
- `match-constants` MUST
- `match-default-threshold` MUST
- `match-dormant-only` MUST
- `match-exclude-assigned` MUST
- `match-threshold-filter` MUST
- `match-order` MUST
- `match-greedy` MUST
- `match-unmatched` MUST
- `match-unassigned` MUST
- `match-result-order` MUST
- `match-substring-default` MUST
- `candidate-match-shape` MUST
- `match-result-equality` MUST
- `match-no-side-effects` MUST

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

