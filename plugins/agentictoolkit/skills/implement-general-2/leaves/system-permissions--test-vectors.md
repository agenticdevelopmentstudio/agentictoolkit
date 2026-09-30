<!-- leaf: implement-general-2/system-permissions--test-vectors · source: system-permissions.md -->

# SystemPermissions

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| system-permissions-001 | automation-mapping | `automationStatus(0)` | `granted` |
| system-permissions-002 | automation-mapping | `automationStatus(-1743)` | `denied` |
| system-permissions-003 | automation-mapping, undetermined-meaning | `automationStatus(-1744)`; `automationStatus(-600)` | `undetermined` for both |
| system-permissions-004 | automation-mapping | Checker with stub probe returning -1743; `status(.automation(targetBundleID: "com.googlecode.iterm2"))` | `denied` |
| system-permissions-005 | automation-probe-flag | Recording stub probe; call `status(.automation(targetBundleID: "com.googlecode.iterm2"))`, then `request` of the same | After status: last bundle id `"com.googlecode.iterm2"`, last `promptIfNeeded == false`; after request: `promptIfNeeded == true` |
| system-permissions-006 | is-granted | Stub probe returning 0, -1743, -600; `isGranted(.automation(targetBundleID: "x"))` | `true`, `false`, `false` |
| system-permissions-007 | notifications-mapping | `notificationStatus` of `authorized`, `denied`, `notDetermined` | `granted`, `denied`, `undetermined` |
| system-permissions-008 | notifications-mapping | `notificationStatus` of `provisional`, `ephemeral` | `granted` for both |
| system-permissions-009 | location-mapping, location-when-in-use-denied | `locationStatus` of `authorizedAlways`, raw value 4 (when in use), `denied`, `restricted`, `notDetermined` | `granted`, `denied`, `denied`, `denied`, `undetermined` |
| system-permissions-010 | microphone-mapping | `captureStatus` of `authorized`, `denied`, `restricted`, `notDetermined` | `granted`, `denied`, `denied`, `undetermined` |
| system-permissions-011 | keychain-mapping | `keychainStatus` of `errSecSuccess`, `errSecItemNotFound`, `errSecUserCanceled`, `errSecAuthFailed` | `granted`, `undetermined`, `denied`, `denied` |
| system-permissions-012 | display-name | `displayName` of each case (automation target `"com.googlecode.iterm2"`, keychain service `"Claude Code-credentials"`) | `"Accessibility"`, `"Notifications"`, `"Automation"`, `"Location"`, `"Microphone"`, `"Screen Capture"`, `"Keychain"` |
| system-permissions-013 | identifier-token-derived, explanation-keychain-service | `.keychain(service: "Claude Code-credentials")` and `.keychain(service: "Stenographer Claude Accounts")` | Tokens `"keychain-claude-code-credentials"` and `"keychain-stenographer-claude-accounts"`; explanations differ; first contains `"Claude Code-credentials"` |
| system-permissions-014 | identifier-token-derived | `.automation(targetBundleID: "com.googlecode.iterm2").identifierToken` | `"automation-com-googlecode-iterm2"` |
| system-permissions-015 | identifier-token-fixed | `.screenCapture.identifierToken` | `"screen-capture"` |
| system-permissions-016 | system-image-name, explanation-default | Every case | Non-empty `systemImageName` and non-empty `explanation` |
| system-permissions-017 | settings-pane-url-tcc | `settingsPaneURL` of `.accessibility`, `.automation(targetBundleID: "com.googlecode.iterm2")`, `.location`, `.microphone`, `.screenCapture` | `...security?Privacy_Accessibility`, `...?Privacy_Automation`, `...?Privacy_LocationServices`, `...?Privacy_Microphone`, `...?Privacy_ScreenCapture` |
| system-permissions-018 | settings-pane-url-notifications | `.notifications.settingsPaneURL` in a process with a bundle id | Starts with `x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=` |
| system-permissions-019 | settings-pane-url-keychain, action-title | `.keychain(service: "Claude Code-credentials")`; `.accessibility` | Keychain: `settingsPaneURL == nil`, `actionTitle == "Allow…"`; accessibility: `actionTitle == "Open Settings"` |
| system-permissions-020 | action-title-all | `Permission.ActionTitle.all` | `["Open Settings", "Allow…"]` |
| system-permissions-021 | explanation-automation-target | `.automation(targetBundleID: "com.googlecode.iterm2").explanation(namingAutomationTarget: { _ in "iTerm" })` | `"Needed to find, raise and open windows in iTerm."` |
| system-permissions-022 | ledger-key, ledger-values | `KeychainPermissionLedger.record(.granted, service: "Claude Code-credentials")`, then `status(service:)` | Defaults key `"permission.keychain-claude-code-credentials.status"` holds `"granted"`; status is `granted` |
| system-permissions-023 | ledger-undetermined-erases, ledger-forget | After 022, `forget(service: "Claude Code-credentials")` | Key removed; `status(service:)` is `undetermined` |
| system-permissions-024 | ledger-record-osstatus | `record(errSecUserCanceled as OSStatus, service: "S")` | `status(service: "S")` is `denied` |
| system-permissions-025 | ledger-values | Defaults key for service `"S"` set to `"maybe"` | `status(service: "S")` is `undetermined` |
| system-permissions-026 | keychain-status-no-access | `status(.keychain(service: "S"))` with ledger holding `"denied"` and no keychain item | Returns `denied`; no keychain query is issued |
| system-permissions-027 | location-request-settled | Location authorization already `denied`; `request(.location)` | Returns `denied` immediately without waiting |
| system-permissions-028 | location-request-timeout | Location `notDetermined`; `request(.location)`; no decision for 120 s | Resumes after 120 s with the then-current status (`undetermined` if still undecided) |

Vectors 001–012 (location arm included), 013, 016–019 derive from `SystemPermissionCheckerTests.swift` and `PermissionMetadataTests.swift`. Vectors for accessibility, screen capture and the live notification/microphone/keychain request flows are manual: they depend on real TCC and keychain state that a test process cannot control, as the `AutomationProbing` doc comment states.
