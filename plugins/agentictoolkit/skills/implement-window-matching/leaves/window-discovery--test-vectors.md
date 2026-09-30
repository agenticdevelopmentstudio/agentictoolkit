<!-- leaf: implement-window-matching/window-discovery--test-vectors · source: window-matching-window-discovery.md -->

# WindowDiscoveryViewModel

## Conformance Test Vectors

Vectors 001–005 come from `WindowDiscoveryMatchingTests.swift`; the rest trace to `WindowDiscoveryViewModel.swift`. Enumeration vectors assume a fake engine and fake running-app list.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wdisc-001 | heuristic-pattern, pattern-or-title-contains | `matches` with app `"Xcode"`, title `"MyApp — ContentView.swift"`, projectName `"MyApp"` | `true` |
| wdisc-002 | raw-title-fallback, pattern-or-title-contains | app `"SomeEditor"` (no heuristic), title `"Working on MyApp now"`, projectName `"MyApp"` | `true` |
| wdisc-003 | pattern-or-title-contains | app `"Xcode"`, title `"OtherProject — File.swift"`, projectName `"MyApp"` | `false` |
| wdisc-004 | empty-project-never-matches | app `"Xcode"`, title `"MyApp — File.swift"`, projectName `""` | `false` |
| wdisc-005 | unknown-project-never-matches | app `"Xcode"`, title `"MyApp — File.swift"`, projectName `"Unknown"` | `false` |
| wdisc-006 | pattern-or-title-contains | app `"SomeEditor"`, title `"MYAPP notes"`, projectName `"myapp"` | `true` (case-insensitive) |
| wdisc-007 | discovery-permission-gate, denied-keeps-apps | Accessibility not granted; `apps` already holds 2 entries; call `discoverWindows()` | synchronously `isLoading == false`, `accessibilityDenied == true`, `apps` still has the 2 entries, engine never queried |
| wdisc-008 | discovery-resets-flags, results-published-on-main | granted; `accessibilityDenied` previously `true`; call `discoverWindows()` | immediately `isLoading == true`, `accessibilityDenied == false`; later, on main, `apps` set then `isLoading == false` |
| wdisc-009 | untitled-windows-dropped, foreign-pid-dropped, windowless-apps-omitted | regular apps A (pid 10) and B (pid 20); engine windows: pid 10 `"Doc"`, pid 10 `""`, pid 30 `"Other"` | `apps` holds only A with one window `"Doc"`; B and pid 30 absent |
| wdisc-010 | regular-apps-only | an accessory-policy app (pid 40) owns a titled window | pid 40 absent from `apps` |
| wdisc-011 | match-first-sort, alphabetical-sort | apps `"zeta"` (has match), `"Beta"` (no match), `"alpha"` (no match) | order `"zeta"`, `"alpha"`, `"Beta"` |
| wdisc-012 | app-has-match | `DiscoveredApp` with windows `isMatch` = false, true | `hasMatch == true`; with all false, `hasMatch == false` |
| wdisc-013 | unknown-app-name | regular app with nil localized name owns a titled window | its `DiscoveredApp.name == "Unknown"` |
| wdisc-014 | window-order-preserved, group-by-pid | engine reports pid 10 windows `"B"` then `"A"` | one `DiscoveredApp` for pid 10 with windows `"B"`, `"A"` in that order |
| wdisc-015 | activation-success-callback | engine focus succeeds; `onWindowActivated` set | callback invoked exactly once |
| wdisc-016 | activation-failure-logged, activation-failure-no-callback, activation-error-not-rethrown | engine focus throws window-not-found | error log with the pid and description; callback not invoked; `activateWindow` returns normally |
| wdisc-017 | settings-request, settings-no-refresh | call `openAccessibilitySettings()` | permission request issued once; `apps`, `isLoading`, `accessibilityDenied` unchanged |
| wdisc-018 | weak-owner | model released after `discoverWindows()` returns but before the background block runs | engine not queried; no publish |
| wdisc-019 | duplicate-pid-first-wins | snapshot lists pid 10 as `"First"` then `"Second"` | the `DiscoveredApp` for pid 10 is named `"First"` |
