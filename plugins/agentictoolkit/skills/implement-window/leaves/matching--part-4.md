<!-- leaf: implement-window/matching--part-4 · source: window-matching.md -->

# Window Matching — continued (part 4)

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
