<!-- leaf: implement-window/matching--test-vectors · source: window-matching.md -->

# Window Matching

## Conformance Test Vectors

Vectors 001 to 013 are derived from `SystemWindowMatcherTests` and `HeuristicTests`; the rest from the source. Windows use `display: 99` and fingerprints `display: 0` unless stated.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| window-matching-001 | score-app-gate | fingerprint (Xcode, "Proj", substring); window (Other, "Proj") | score 0 |
| window-matching-002 | score-app-only | fingerprint (Terminal, "", appOnly); window (Terminal, "anything") | score 80 |
| window-matching-003 | score-substring-contains, match-constants | fingerprint (TestApp, "a", substring); window (TestApp, "banana") | score 0 (pattern shorter than 2) |
| window-matching-004 | score-substring-contains | fingerprint (TestApp, "ban", substring); window (TestApp, "banana") | score 60 |
| window-matching-005 | score-regex | fingerprint (TestApp, regex source JIRA-backslash-d-plus, regex); windows "JIRA-1234 details" and "no ticket" | 80 and 0 |
| window-matching-006 | score-display-bonus | fingerprint (Terminal, "", appOnly, display 7); window (Terminal, "x", display 7) | score 90 |
| window-matching-007 | match-threshold-filter, match-unmatched, match-unassigned, match-default-threshold | one context with a dormant snapshot of fingerprint (TestApp, "ban", substring); live window id 5 "banana" | default threshold: matched empty, 1 unmatched snapshot, unassigned ids [5]; threshold 60: matched count 1 |
| window-matching-008 | match-order, match-greedy | contexts A (UUID ...0001) and B (...0002), each one dormant appOnly Terminal snapshot; windows 10 and 20 (Terminal) | two runs return equal results; matched count 2 |
| window-matching-009 | match-result-equality | two `MatchResult`s differing only in the unmatched snapshot's IDs | not equal; each equals itself |
| window-matching-010 | parser-separators, parser-first-separator-wins | `XcodeHeuristic().extractPattern` on "MyApp" + em dash + "ContentView.swift", then the en-dash variant | "MyApp" both times |
| window-matching-011 | custom-fingerprint-regex, custom-fingerprint-unmatched | regex rule (Jira, JIRA-backslash-d-plus); titles "JIRA-1234 — details" and "no ticket here" | pattern is the regex source, strategy `.appAndTitleRegex`; then nil |
| window-matching-012 | custom-fingerprint-substring | substring rule (Notes, "Daily"); title "Daily Standup" | ("Daily", `.appAndTitleSubstring`) |
| window-matching-013 | registry-is-built-in, registry-custom-overrides | default registry; then `registerCustomRules` with a rule for "Xcode" | `isBuiltIn("Xcode")` true, then false |
| window-matching-014 | rule-empty-pattern | substring rule with `titlePattern` "" ; title "anything" | `matchTitle` returns nil |
| window-matching-015 | rule-substring-match | substring rule "dash"; title "My DASHBOARD" | returns "dash" (the pattern, not "DASH") |
| window-matching-016 | rule-regex-non-empty | regex rule ".*"; title "" | nil |
| window-matching-017 | rule-regex-invalid | regex rule with pattern "(" ; title "x" | nil, one error logged |
| window-matching-018 | rule-default-name | `CustomHeuristicRule(appName: "Safari", titlePattern: "Docs")` | `name` is "Safari - Docs" |
| window-matching-019 | fingerprint-fallback | window (UnknownApp, "Report.pdf", display 3) | fingerprint (UnknownApp, "Report.pdf", `.appAndTitleSubstring`, 3) |
| window-matching-020 | fingerprint-empty-title | window (UnknownApp, "") | fingerprint strategy `.appOnly`, pattern "" |
| window-matching-021 | score-exact | fingerprint (UnknownApp, "report", appAndTitleExact); windows "REPORT" and "report 2" | 80 and 0 |
| window-matching-022 | score-substring-direction | fingerprint (UnknownApp, "project alpha", substring); window "alpha" | score 0 |
| window-matching-023 | score-regex-invalid | fingerprint (TestApp, "[", appAndTitleRegex); window "[" | score 0, one error logged |
| window-matching-024 | match-exclude-assigned, match-dormant-only | context with a live snapshot (windowID 7) and a dormant appOnly Terminal snapshot; live windows 7 and 8 (Terminal) | matched pairs the dormant snapshot with window 8; window 7 absent from `unassignedWindows` |
| window-matching-025 | registry-case-insensitive, registry-last-wins | registry with no heuristics; `register` H1 for "Foo" then H2 for "foo" | `heuristic(for: "FOO")` is H2; `heuristic(for: "Bar")` nil |
| window-matching-026 | registry-custom-clear | default registry; `registerCustomRules([rule for "Xcode"])` then `registerCustomRules([])` | `heuristic(for: "Xcode")` is `XcodeHeuristic`; `customRules` empty |
| window-matching-027 | store-load-missing | store on an empty temporary directory | `loadRules()` returns [] |
| window-matching-028 | store-save-directory, store-save-format, store-load-decode | store on a non-existent nested directory; save two rules; load | directory created; file is sorted-key pretty JSON; loaded rules equal saved rules |
| window-matching-029 | store-load-errors | `heuristics.json` containing "not json" | `loadRules()` throws a decoding error |
| window-matching-030 | store-remove-all | save rules, call `removeAll()` twice | file gone, directory remains, second call does not throw |
| window-matching-031 | match-substring-default | dormant substring snapshot (TestApp, "ban", display 1); window "banana" on display 1 | score 70; not matched at default threshold |
| window-matching-032 | parser-trim, parser-no-separator | `components(of: "  solo  ")` | ["solo"] |
