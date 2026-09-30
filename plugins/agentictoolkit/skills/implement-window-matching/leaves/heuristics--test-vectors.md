<!-- leaf: implement-window-matching/heuristics--test-vectors · source: window-matching-heuristics.md -->

# Window Matching Heuristics

## Conformance Test Vectors

Titles below write the em dash as "—" (U+2014) and the en dash as "–"
(U+2013). Vectors marked (test) are asserted in `HeuristicTests.swift`; the
rest are traced to the heuristic's code and doc-comment examples.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wmh-001 | xcode-first-component | `XcodeHeuristic().extractPattern(from: "MyApp — ContentView.swift")` (test) | "MyApp" |
| wmh-002 | separator-set, xcode-first-component | `XcodeHeuristic().extractPattern(from: "MyApp – ContentView.swift")` (test) | "MyApp" |
| wmh-003 | xcode-no-separator-whole-title | `XcodeHeuristic().extractPattern(from: "MyApp")` | "MyApp" |
| wmh-004 | xcode-first-component | "QualityTime — ContentView.swift (Edited)" | "QualityTime" |
| wmh-005 | xcode-empty-first-component-nil | "   " (three spaces) | `nil` |
| wmh-006 | empty-title-nil | "" passed to each of the five heuristics | `nil` from all five |
| wmh-007 | separator-hyphen-not-split, xcode-no-separator-whole-title | Xcode, "MyApp - ContentView.swift" | "MyApp - ContentView.swift" |
| wmh-008 | separator-first-match-wins | `HeuristicTitleParser.components(of: "A — B – C")` | `["A", "B – C"]` |
| wmh-009 | separator-absent-single-component | `HeuristicTitleParser.components(of: "  zsh ")` | `["zsh"]` |
| wmh-010 | separator-components-trimmed | `HeuristicTitleParser.components(of: "a — ")` | `["a", ""]` |
| wmh-011 | warp-path-last-component, warp-strip-branch | `WarpHeuristic().extractPattern(from: "mike - ~/projects/myapp (develop)")` (test) | "myapp" |
| wmh-012 | warp-root-path-nil | `WarpHeuristic().extractPattern(from: "user - / (main)")` (test) | `nil` |
| wmh-013 | warp-strip-dirty-indicator, warp-strip-branch | "Claude - QualityTime (main) *" | "QualityTime" |
| wmh-014 | warp-plain-remainder | "mike - Documents" | "Documents" |
| wmh-015 | warp-requires-hyphen-separator | "QualityTime — main" | `nil` |
| wmh-016 | warp-remainder-after-first-separator | "a - b - c" | "b - c" |
| wmh-017 | warp-path-last-component | "mike - ~/projects/myapp/" | "myapp" |
| wmh-018 | brave-strip-suffix | "GitHub - Pull Requests - Brave" | "GitHub - Pull Requests" |
| wmh-019 | brave-bare-app-name-nil | "Brave" | `nil` |
| wmh-020 | brave-strip-suffix | " - Brave" | `nil` |
| wmh-021 | brave-fallback-whole-title, brave-suffix-case-sensitive | "Docs - Brave Browser" | "Docs - Brave Browser" |
| wmh-022 | vscode-default-first | `VSCodeHeuristic().extractPattern(from: "temporal — api.go")` (test) | "temporal" |
| wmh-023 | vscode-filename-first-prefers-last, vscode-filename-test | "settings.json — myproject" | "myproject" |
| wmh-024 | vscode-default-first | "api.go — main.ts" | "api.go" |
| wmh-025 | vscode-single-component, vscode-generic-titles | "Welcome" | `nil` |
| wmh-026 | vscode-generic-last-returns-first | "Welcome — Visual Studio Code" | "Welcome" (the doc comment says `nil`; see the open question on vscode-welcome-doc-contract) |
| wmh-027 | vscode-default-first | " — foo" (leading space, empty first component) | `nil` |
| wmh-028 | vscode-filename-test | "notes.JSON — proj" | "proj" (extension match is case-insensitive) |
| wmh-029 | terminal-second-component, terminal-strip-one-dash | "mfullerton — -zsh — 80x24" | "zsh" |
| wmh-030 | terminal-second-component | "mfullerton — ssh user@host" | "ssh user@host" |
| wmh-031 | terminal-strip-one-dash | "u — --x" | "-x" |
| wmh-032 | terminal-strip-one-dash | "u — -" | `nil` |
| wmh-033 | terminal-single-component | "bash" | "bash" |
| wmh-034 | terminal-strategy-app-only, default-fingerprint-pattern | `TerminalHeuristic().fingerprintPattern(for: "u — vim — 80x24")` | `(pattern: "vim", strategy: .appOnly)` |
| wmh-035 | default-strategy-substring, default-fingerprint-pattern | `XcodeHeuristic().fingerprintPattern(for: "MyApp — a.swift")` | `(pattern: "MyApp", strategy: .appAndTitleSubstring)` |
| wmh-036 | default-fingerprint-pattern | `BraveHeuristic().fingerprintPattern(for: "Brave")` | `nil` |
| wmh-037 | xcode-identity, warp-identity, brave-identity, vscode-identity, terminal-identity | read `name` and `appNames` of each built-in | "Xcode"/`["Xcode"]`; "Warp"/`["Warp"]`; "Brave Browser"/`["Brave Browser"]`; "VS Code"/`["Code", "Visual Studio Code", "Cursor"]`; "Terminal"/`["Terminal"]` |
| wmh-038 | heuristic-pure, heuristic-sendable | call `extractPattern(from:)` on one shared instance from many concurrent tasks with the same title | every call returns the same value; no data race is reported under strict concurrency checking |
