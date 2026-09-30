<!-- leaf: implement-window/matching--edge-cases · source: window-matching.md -->

# Window Matching

**Rules** (cite as `implement-window/matching--edge-cases#<slug>`):

- `empty-window-title` MUST — fingerprint(window:) MUST fall back to .appOnly, so any same-app window later scores at least 80 against it.
- `empty-stored-pattern-under-substring` MUST — a .appAndTitleSubstring fingerprint with titlePattern "" MUST score 80 only against a window whose live pattern is …
- `empty-rule-pattern` MUST — matchTitle MUST return nil, so a CustomHeuristic with an empty pattern never fingerprints and the matcher falls back to …
- `empty-app-name-on-a-rule` MUST — the rule MUST be registered under the empty key and apply only to windows whose owner name is empty; nothing rejects it.
- `invalid-regex-in-a-rule-or-fingerprint` MUST — MUST yield no match and log an error; the regex is recompiled and the error re-logged on every call, with no caching.
- `zero-width-regex` MUST — patterns that match the empty string MUST NOT count as matches, in both CustomHeuristicRule.matchTitle and matcher …
- `title-content-containing` MUST — MUST be split as if it were a separator when no em dash is present (accepted trade-off).
- `non-ascii-case-folding` MUST — rule substring matching MUST use a locale-aware case-insensitive comparison, while scoring and registry lookup MUST use …
- `no-contexts-or-no-live-windows` MUST — matchWindows MUST return empty matched; with no live windows every dormant snapshot MUST be in unmatchedSnapshots; with …
- `stale-live-snapshot` MUST — a snapshot whose windowID names a window not in liveWindows MUST NOT be re-matched (it is not dormant) and MUST NOT …
- `duplicate-snapshot-ids-across-contexts` MUST — acceptance MUST be keyed by snapshotID alone, so once one is matched every other dormant snapshot with the same ID MUST …
- `duplicate-window-ids-in-livewindows` MUST — at most one of them MUST be matched; the duplicates MUST all be omitted from unassignedWindows once one is matched.
- `threshold-at-or-below-0` MUST — every scored pair, including 0-score pairs, MUST become a candidate, so any dormant snapshot can be matched to any …
- `threshold-above-90` MUST — nothing MUST be matched.
- `missing-heuristics-file` MUST — loadRules() MUST return [] rather than throw.
- `corrupt-or-unreadable-heuristics-file` MUST — loadRules() MUST throw; the store does not repair or back up the file.
- `unwritable-root-directory` MUST — saveRules(_:) MUST throw the file-system error; with the atomic write, the prior file MUST remain intact.
- `concurrent-registry-mutation` MUST — each registry call MUST be atomic; a matchWindows run concurrent with registerCustomRules MAY score pairs against a mix …
- `concurrent-store-access` MUST — not serialized; two processes or threads saving at once MUST each produce a complete file, with the last atomic write …

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
