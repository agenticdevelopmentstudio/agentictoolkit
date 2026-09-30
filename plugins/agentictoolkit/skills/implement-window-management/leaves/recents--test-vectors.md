<!-- leaf: implement-window-management/recents--test-vectors · source: window-management-recents.md -->

# Window Management Recents

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| recents-001 | use-system-follows-default | `ReopenOnLaunchPolicy.useSystem.shouldReopen(systemDefault: true)` | `true` (`ReopenOnLaunchPolicyTests`) |
| recents-002 | use-system-follows-default | `ReopenOnLaunchPolicy.useSystem.shouldReopen(systemDefault: false)` | `false` (`ReopenOnLaunchPolicyTests`) |
| recents-003 | always-reopens | `ReopenOnLaunchPolicy.always.shouldReopen(systemDefault:)` with `false`, then `true` | `true`, then `true` (`ReopenOnLaunchPolicyTests`) |
| recents-004 | never-reopens | `ReopenOnLaunchPolicy.never.shouldReopen(systemDefault:)` with `false`, then `true` | `false`, then `false` (`ReopenOnLaunchPolicyTests`) |
| recents-005 | display-name-use-system, display-name-always, display-name-never | `displayName` of `useSystem`, `always`, `never` | `"Use System Setting"`, `"Always"`, `"Never"` (`ReopenOnLaunchPolicyTests`) |
| recents-006 | policy-case-iterable, policy-cases | `ReopenOnLaunchPolicy.allCases` | 3 elements: `useSystem`, `always`, `never` (count asserted in `ReopenOnLaunchPolicyTests`) |
| recents-007 | policy-raw-values | `rawValue` of each case; `ReopenOnLaunchPolicy(rawValue: "always")`; `ReopenOnLaunchPolicy(rawValue: "sometimes")` | `"useSystem"`, `"always"`, `"never"`; `.always`; `nil` |
| recents-008 | policy-codable | JSON-encode `.never`, then decode the result | Encoded JSON is the string `"never"`; decodes back to `.never` |
| recents-009 | policy-equatable | `.always == .always`; `.always == .never` | `true`; `false` |
| recents-010 | reopen-decision-pure | Set `NSQuitAlwaysKeepsWindows = true` in the app domain, then call `ReopenOnLaunchPolicy.never.shouldReopen(systemDefault: false)` | `false`; the preference has no effect on the result |
| recents-011 | system-default-key | Standard defaults with `NSQuitAlwaysKeepsWindows = true` | `ReopenOnLaunchPolicy.systemDefault == true` |
| recents-012 | system-default-absent | Standard defaults with `NSQuitAlwaysKeepsWindows` removed from every searched domain | `ReopenOnLaunchPolicy.systemDefault == false` |
| recents-013 | system-default-uncached | Read `systemDefault` with the key `false`, set the key `true`, read again | First read `false`, second read `true` |
| recents-014 | system-default-inverted-label | "Close windows when quitting an application" checked in System Settings (stores `NSQuitAlwaysKeepsWindows = false`) | `systemDefault == false`; `useSystem.shouldReopen(systemDefault: systemDefault) == false` |
| recents-015 | system-default-read-only | Snapshot the standard defaults, read `systemDefault` and every `displayName` | Defaults unchanged |
| recents-016 | recent-count-key, recent-count-default | Empty settings store; read `UserSettings.recentWindowsCount.currentValue` | `10`; `UserSettings.recentWindowsCount.name == "recentWindowsCount"` |
| recents-017 | recent-count-storage-form | Set `UserSettings.recentWindowsCount.value = 7` with the default provider | `UserDefaults.standard.integer(forKey: "recentWindowsCount") == 7`, stored as a number |
| recents-018 | policy-setting-key, policy-setting-default | Empty settings store; read `UserSettings.reopenOnLaunchPolicy.currentValue` | `.useSystem`; `name == "reopenOnLaunchPolicy"` |
| recents-019 | policy-setting-storage-form | Set `UserSettings.reopenOnLaunchPolicy.value = .always` with the default provider | `UserDefaults.standard.data(forKey: "reopenOnLaunchPolicy")` holds the JSON string `"always"`; reading the setting returns `.always` |
| recents-020 | policy-setting-decode-fallback | Store data for the JSON string `"sometimes"` under `"reopenOnLaunchPolicy"` | Reading the setting returns `.useSystem`; nothing is thrown or logged |
| recents-021 | settings-not-secure | Inspect `isSecure` on both settings | `false` for both |
| recents-022 | settings-observable | Subscribe to `UserSettings.reopenOnLaunchPolicy.$currentValue`, then set `.value = .never` | Subscriber receives `.never` |
| recents-023 | recent-count-mirror | `recentWindowsCount.value = 7`, call `applyRecentDocumentCountFromSettings()`; then `3`, call again | `UserDefaults.standard.integer(forKey: "NSRecentDocumentsLimit")` is `7`, then `3` (`WindowManagerRecentsTests.testApplyRecentDocumentCountFromSettingsWritesUserDefault`) |
| recents-024 | recent-count-mirror-live | Touch `WindowManager.shared`, set `recentWindowsCount.value = 12`, check on the next main-queue turn | `NSRecentDocumentsLimit == 12` with no explicit apply call (`WindowManagerRecentsTests.testSettingChangePropagatesViaCombineSink`) |
| recents-025 | policy-consumed-for-documents-only | `reopenOnLaunchPolicy = .never`; call `ProjectWindowManager.restoreOpenProjects()` with a project whose window was open last session and whose folder exists | The project window reopens; the policy is not consulted |
| recents-026 | settings-main-actor | Read `UserSettings.recentWindowsCount.currentValue` from a nonisolated context with no `await` | Rejected at compile time under strict concurrency |
| recents-027 | no-errors, no-network-no-files | Call every public member of both files | None throws; no file, network, or process activity beyond the user-defaults reads and writes |
