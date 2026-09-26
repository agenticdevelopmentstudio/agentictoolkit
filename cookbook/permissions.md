---
id: b4cfbb31-cacc-4532-97c3-03e53852e8d3
title: SystemPermissions
domain: agentictoolkit://cookbook/permissions
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Daemon-safe tri-state model, status probe and request flow for macOS privacy
  permissions, plus a keychain grant ledger.
platforms:
- swift
- macos
tags:
- permissions
- macos
- async
depends-on: []
related:
- agentictoolkit://cookbook/permissions-ui/permission-row-view
- agentictoolkit://cookbook/permissions-ui/permissions-panel-view
references:
- https://developer.apple.com/documentation/coreservices/1446026-aedeterminepermissiontoautomatetarget
approved-by: ''
approved-date: ''
---

# SystemPermissions

## Overview

SystemPermissions is the Foundation-level (AppKit-free, daemon-linkable) permissions layer of AgenticToolkit. It consists of:

- `Permission` — an enum of the macOS privacy grants a host app may need (`accessibility`, `notifications`, `automation(targetBundleID:)`, `location`, `microphone`, `screenCapture`, `keychain(service:)`) with per-case metadata: `displayName`, `identifierToken`, `systemImageName`, `explanation`, `settingsPaneURL`, `actionTitle`.
- `PermissionStatus` — the tri-state result `granted` / `denied` / `undetermined`.
- `PermissionChecking` — the protocol with `status(_:)` (never prompts) and `request(_:)` (surfaces the system flow), plus the `isGranted(_:)` convenience.
- `SystemPermissionChecker` — the production conformance over the real macOS APIs, with the Apple Events probe injected through `AutomationProbing` (`SystemAutomationProbe` in production).
- `KeychainPermissionLedger` — a `UserDefaults`-backed record of what the app last learned about reading a given keychain item, because macOS offers no way to ask.

Use it wherever an app or daemon has to show or obtain a privacy grant; the UI that renders it lives in [PermissionRowView](agentictoolkit://cookbook/permissions-ui/permission-row-view) and [PermissionsPanelView](agentictoolkit://cookbook/permissions-ui/permissions-panel-view).

## Behavioral Requirements

### Data shapes

- **permission-cases**: `Permission` MUST have exactly seven cases: `accessibility`, `notifications`, `automation(targetBundleID: String)`, `location`, `microphone`, `screenCapture`, `keychain(service: String)`.
- **permission-value-semantics**: `Permission` MUST be `Sendable` and `Hashable`; two `automation` values with different `targetBundleID`s, or two `keychain` values with different `service`s, MUST be unequal (each is a distinct grant).
- **status-tri-state**: `PermissionStatus` MUST have exactly three cases, `granted`, `denied` and `undetermined`, and MUST be `Sendable` and `Equatable`.
- **undetermined-meaning**: `undetermined` MUST mean "cannot prove granted or denied" (never asked, target not running, no keychain item, timeout), and MUST NOT be used for a known refusal.

### Permission metadata

- **display-name**: `displayName` MUST return `"Accessibility"`, `"Notifications"`, `"Automation"`, `"Location"`, `"Microphone"`, `"Screen Capture"` and `"Keychain"` for the seven cases respectively, ignoring associated values.
- **identifier-token-fixed**: `identifierToken` MUST return `"accessibility"`, `"notifications"`, `"location"`, `"microphone"` and `"screen-capture"` for the five cases without associated values.
- **identifier-token-derived**: For `automation(targetBundleID:)` and `keychain(service:)`, `identifierToken` MUST be the prefix `"automation-"` or `"keychain-"` followed by the associated string lowercased, split on every non-alphanumeric character, with empty pieces dropped, and joined with `"-"`.
- **system-image-name**: `systemImageName` MUST return the SF Symbol names `"hand.raised"`, `"bell.badge"`, `"gearshape.2"`, `"location"`, `"mic"`, `"display"` and `"key.fill"` for the seven cases respectively.
- **explanation-default**: `explanation` MUST equal `explanation(namingAutomationTarget:)` called with the identity function, so an Automation target is named by its raw bundle id.
- **explanation-automation-target**: For `automation(targetBundleID:)`, `explanation(namingAutomationTarget:)` MUST call the supplied closure with the bundle id and embed its result in `"Needed to find, raise and open windows in <name>."`.
- **explanation-keychain-service**: For `keychain(service:)`, the explanation MUST embed the service name in curly double quotes (U+201C, U+201D), so two services yield two different sentences.
- **settings-pane-url-tcc**: `settingsPaneURL` MUST return the `x-apple.systempreferences:com.apple.preference.security?Privacy_<Pane>` URL for `accessibility` (`Privacy_Accessibility`), `automation` (`Privacy_Automation`, one URL for every target), `location` (`Privacy_LocationServices`), `microphone` (`Privacy_Microphone`) and `screenCapture` (`Privacy_ScreenCapture`).
- **settings-pane-url-notifications**: For `notifications`, `settingsPaneURL` MUST be `x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=<bundle id>` when the main bundle has a non-empty bundle identifier, and the same URL without the `?id=` query otherwise.
- **settings-pane-url-keychain**: For `keychain(service:)`, `settingsPaneURL` MUST be `nil`, because keychain access is not a TCC permission and System Settings lists no pane for it.
- **settings-pane-url-invalid-traps**: If a pane URL string fails to parse as a `URL`, `settingsPaneURL` MUST terminate the process with a precondition failure naming the string rather than return `nil`.
- **action-title**: `actionTitle` MUST be `Permission.ActionTitle.allow` (`"Allow…"`, with U+2026) when the permission has no settings pane, and `Permission.ActionTitle.openSettings` (`"Open Settings"`) otherwise.
- **action-title-all**: `Permission.ActionTitle.all` MUST list exactly `[openSettings, allow]` so a caller can size a control to the widest title.

### `PermissionChecking` contract

- **checker-sendable**: `PermissionChecking` and `AutomationProbing` MUST be `Sendable` protocols; `SystemPermissionChecker` and `SystemAutomationProbe` are `Sendable` structs usable from any isolation domain.
- **status-no-prompt**: `status(_:)` MUST NOT show any system prompt for any permission, and MUST be safe to call repeatedly (it is polled on every app activation by the panel).
- **request-surfaces-flow**: `request(_:)` MUST surface the system request flow for the permission when one exists and MUST return the resulting `PermissionStatus`; its result is `@discardableResult`.
- **is-granted**: `isGranted(_:)` MUST return `true` only when `status(_:)` returns `granted`, and `false` for both `denied` and `undetermined`.

### Status mapping per permission

- **accessibility-status**: `status(.accessibility)` MUST return `granted` when the process is AX-trusted and `denied` otherwise; it never returns `undetermined`.
- **accessibility-request**: `request(.accessibility)` MUST ask for AX trust with the prompt option set (key `"AXTrustedCheckOptionPrompt"` = `true`) and return `granted` if trusted at that moment, else `denied`; it does not wait for the user to act in System Settings.
- **notifications-mapping**: Notification authorization MUST map `authorized`, `provisional` and `ephemeral` to `granted`; `denied` to `denied`; `notDetermined` and any unknown future value to `undetermined`.
- **notifications-request**: `request(.notifications)` MUST request authorization for alert and sound, discard any error the request throws, and then return a fresh `status(.notifications)`.
- **automation-probe-flag**: `status(.automation(targetBundleID:))` MUST call the injected probe with `promptIfNeeded: false`, and `request(.automation(targetBundleID:))` MUST call it with `promptIfNeeded: true`; both MUST forward the target bundle id unchanged.
- **automation-mapping**: An Automation probe status of `noErr` (0) MUST map to `granted`, `errAEEventNotPermitted` (-1743) to `denied`, and every other value — including -1744 (consent required) and -600 (target not running) — to `undetermined`.
- **automation-off-cooperative-pool**: The Automation probe MUST run on a GCD global queue at `userInitiated` QoS, bridged back with a checked continuation, never on the calling Swift-concurrency thread, because with `promptIfNeeded: true` it blocks until the user dismisses the consent dialog.
- **automation-probe-no-launch**: `SystemAutomationProbe` MUST check permission for the specific target bundle id (event class and id wildcards) without launching the target app, and MUST return the descriptor-creation `OSStatus` unchanged if the target descriptor cannot be created.
- **microphone-mapping**: Audio capture authorization MUST map `authorized` to `granted`; `denied` and `restricted` to `denied`; `notDetermined` and unknown values to `undetermined`.
- **microphone-request**: `request(.microphone)` MUST request audio access, ignore the returned Bool, and return a fresh `status(.microphone)` so a restriction is distinguished from a first denial.
- **screen-capture-status**: `status(.screenCapture)` MUST return `granted` when screen-capture preflight passes and `denied` otherwise; it never returns `undetermined`, so never-asked reads the same as refused.
- **screen-capture-request**: `request(.screenCapture)` MUST call the system screen-capture request and return `granted` or `denied` from its Bool; after a remembered refusal the system shows nothing and the result is `denied`.
- **location-mapping**: Location authorization MUST map only `authorizedAlways` to `granted`; `authorizedWhenInUse`, `denied` and `restricted` to `denied`; `notDetermined` and unknown values to `undetermined`.
- **location-when-in-use-denied**: A when-in-use location grant MUST read as `denied`, not `undetermined`, so the caller falls back to the Settings pane (Always authorization will not re-prompt once any decision exists).
- **location-single-coordinator**: All location status reads and requests MUST go through one process-wide, `@MainActor`-isolated coordinator that owns a single long-lived location manager, created and receiving delegate callbacks on the main actor.
- **location-request-settled**: `request(.location)` MUST request Always authorization and, when the status before the call was anything other than `notDetermined`, return the current status immediately without waiting.
- **location-request-waits**: When the status before the call was `notDetermined`, `request(.location)` MUST suspend until the authorization changes to a non-`notDetermined` value or the timeout fires, and return the status at that moment.
- **location-request-recheck**: After registering its waiter, the coordinator MUST re-read the authorization status and resume all waiters immediately if it is no longer `notDetermined`, so a decision landing between the request and the wait is not lost.
- **location-request-timeout**: The coordinator MUST resume all waiters with the then-current status 120 seconds after the first waiter registered, if no decision has arrived.
- **location-shared-waiters**: Concurrent `request(.location)` calls made while undetermined MUST share one system prompt and one timeout; only the first waiter starts the timeout.
- **location-resume-once**: Every waiter MUST be resumed exactly once: the coordinator reads and clears the waiter list in one main-actor step with no suspension point, cancels the timeout, then resumes each waiter.
- **location-delegate-ignores-undetermined**: A delegate authorization-change callback reporting `notDetermined` MUST NOT resume waiters.

### Keychain permission

- **keychain-status-no-access**: `status(.keychain(service:))` MUST NOT touch the keychain; it MUST return `KeychainPermissionLedger.status(service:)`.
- **keychain-request-is-read**: `request(.keychain(service:))` MUST perform a real in-process read of a generic-password item for the service, requesting its data (not just attributes), matching one item, across both local and synchronizable keychains, so macOS raises its ACL dialog naming this app.
- **keychain-request-off-cooperative-pool**: The keychain read MUST run on a GCD global queue at `userInitiated` QoS, bridged back with a checked continuation.
- **keychain-mapping**: A keychain read status of `errSecSuccess` MUST map to `granted`, `errSecItemNotFound` to `undetermined`, and every other status (e.g. `errSecAuthFailed`, `errSecUserCanceled`, `errSecInteractionNotAllowed`, `errSecMissingEntitlement`) to `denied`.
- **keychain-request-records**: `request(.keychain(service:))` MUST record the mapped status in `KeychainPermissionLedger` before returning it.
- **keychain-read-discards-bytes**: The keychain read MUST discard the returned item data; only the status is kept.
- **ledger-key**: `KeychainPermissionLedger` MUST store its record in `UserDefaults.standard` under the key `"permission.<identifierToken of .keychain(service:)>.status"`.
- **ledger-values**: The ledger MUST store the string `"granted"` or `"denied"`; `status(service:)` MUST return `granted` or `denied` for those strings and `undetermined` for a missing key or any other value.
- **ledger-undetermined-erases**: `record(.undetermined, service:)` MUST remove the key rather than store a third value.
- **ledger-record-osstatus**: `record(_ status: OSStatus, service:)` MUST map the status with the same rules as **keychain-mapping** and record the result.
- **ledger-forget**: `forget(service:)` MUST be equivalent to `record(.undetermined, service:)`.
- **ledger-persistence**: Ledger records MUST survive app restarts (they persist in the app's standard user defaults) and MUST NOT be revalidated against the keychain on read.
- **keychain-ledger-key-collision**: Distinct keychain service names after normalization are a caller precondition. `identifierToken` collapses case and every run of non-alphanumeric characters, so services such as `"Foo Bar"` and `"foo-bar"` share one ledger key and overwrite each other's grant record; nothing validates or disambiguates service names.

## Appearance

Not applicable — this is a permissions model and system-API checker, not a visual component.

## States

Not applicable — this is a permissions model and system-API checker, not a visual component.

## Accessibility

Not applicable — this is a permissions model and system-API checker, not a visual component.

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

## Edge Cases

- **Empty automation bundle id** (MUST): `automation(targetBundleID: "")` produces the token `"automation-"`; the probe returns whatever non-zero status descriptor creation or the permission check yields, which maps to `undetermined` (per **automation-mapping**).
- **Empty keychain service** (MUST): `keychain(service: "")` produces the token `"keychain-"` and ledger key `"permission.keychain-.status"`; a read with an empty service is issued as-is.
- **Target app not running** (MUST): Automation status for a quit target returns -600 and reads as `undetermined`, never `denied`.
- **No keychain item** (MUST): `request(.keychain(service:))` for a missing item returns `undetermined` and erases any ledger record.
- **Locked keychain or interaction not allowed** (MUST): `errSecInteractionNotAllowed` maps to `denied` and is recorded in the ledger as `"denied"`, even though the cause may be transient.
- **Ledger stale after revocation** (MUST): A user who later removes this app from the item's ACL still reads `granted` from `status(_:)` until the app performs a real read and records the new outcome.
- **Keychain service name collision** : Distinct services that normalize to the same token share one ledger record (see **keychain-ledger-key-collision**).
- **Notification request throws** (MUST): The thrown error is discarded; the call returns the re-read status, so the failure surfaces only as `denied` or `undetermined`.
- **Location prompt closed without decision, Location Services off, or missing usage description** (MUST): `request(.location)` returns after the 120-second timeout with the current status, typically `undetermined`.
- **Location read before the manager has synced** (MUST): `status(.location)` can report `undetermined` on a freshly created coordinator; the single long-lived coordinator exists to limit this.
- **Concurrent location requests** (MUST): Callers arriving while undetermined join the existing waiter list and timeout; all are resumed once with the same status.
- **Late delegate callback or timeout after resume** (MUST): `resumeAll` returns immediately when the waiter list is empty, so no continuation is resumed twice.
- **Cancellation** (MUST): None of `status(_:)` or `request(_:)` observes Swift task cancellation; a cancelled caller still waits for the system dialog, the GCD read, or the 120-second location timeout.
- **Timeouts** (MUST): Only location has a timeout. The Automation probe with `promptIfNeeded: true` and the first keychain read block their GCD thread for as long as the user leaves the dialog open.
- **Screen capture after refusal** (MUST): `request(.screenCapture)` returns `denied` with no dialog; recovery is via the Settings pane.
- **Invalid pane URL string** (MUST): `settingsPaneURL` traps with a precondition failure; with the fixed strings in source this does not occur.
- **Network or offline** (not applicable): No operation performs network I/O; iCloud keychain synchronization is handled by the system.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `automationProbe` (init parameter of `SystemPermissionChecker`) | `any AutomationProbing` | `SystemAutomationProbe()` | Apple Events probe; injected so tests can stub the OSStatus |
| `Bundle.main.bundleIdentifier` | environment | host bundle id | Scopes the Notifications settings-pane URL; omitted when nil or empty |
| `UserDefaults.standard` keys `permission.keychain-<token>.status` | `String` | absent (`undetermined`) | Keychain ledger records |
| Location request timeout | constant | 120 seconds | Not configurable |
| Notification authorization options | constant | alert, sound | Not configurable |
| Host usage descriptions and entitlements | Info.plist / entitlements | — | Supplied by the host app; required by the system for location, microphone and Apple Events prompts to appear |

## Deep Linking

Not applicable: the component registers no inbound URL route; it only vends outbound `x-apple.systempreferences:` URLs via `settingsPaneURL` (see **settings-pane-url-tcc**), and opening them is left to the UI layer.

## Localization

All user-facing strings are hardcoded English literals with no localization lookup:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none) | `Accessibility`, `Notifications`, `Automation`, `Location`, `Microphone`, `Screen Capture`, `Keychain` | `displayName` |
| (none) | `Required to discover and activate terminal windows for your sessions.` | `explanation`, accessibility |
| (none) | `Allows notifications when sessions start, end, or become stale.` | `explanation`, notifications |
| (none) | `Needed to find, raise and open windows in <name>.` | `explanation`, automation |
| (none) | `Records where you are and which Wi-Fi network you're on, so activity can be grouped by place.` | `explanation`, location |
| (none) | `Lets this app record audio from your microphone.` | `explanation`, microphone |
| (none) | `Lets this app read what is on your screen, to capture a still of it or record it.` | `explanation`, screen capture |
| (none) | `Lets this app read the “<service>” item in your keychain directly, instead of asking another tool for it.` | `explanation`, keychain |
| (none) | `Open Settings` | `ActionTitle.openSettings` |
| (none) | `Allow…` | `ActionTitle.allow` |

`identifierToken` is deliberately separate from `displayName` so the displayed copy can be reworded or localized without breaking identifiers.

## Accessibility Options

Not applicable: the component renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: no code path in `SystemPermissionChecker` or `Permission` reads a flag; every case is always available.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

- **Data collected**: Grant state only. `request(.keychain(service:))` reads the item's secret bytes solely to trigger the ACL dialog and discards them (**keychain-read-discards-bytes**); the location path reads authorization status, never coordinates.
- **Storage**: The keychain ledger stores `"granted"`/`"denied"` per service in `UserDefaults.standard`; the key embeds the normalized service name. No secret is stored.
- **Transmission**: Nothing leaves the device.
- **Retention**: Ledger records persist until `forget(service:)`, `record(.undetermined, service:)`, a read returning `errSecItemNotFound`, or removal of the app's defaults.

## Logging

Not applicable: the source contains no logging calls; outcomes are reported only through the returned `PermissionStatus`.

## Platform Notes

- **SwiftUI**: Source platform is Swift on macOS, UI-free. `Permission.swift`, `PermissionStatus.swift`, `PermissionChecking.swift`, `AutomationProbing.swift` hold the pure contract; `SystemAutomationProbe.swift` wraps `AECreateDesc` + `AEDeterminePermissionToAutomateTarget`; `SystemPermissionChecker.swift` holds the per-permission calls (`AXIsProcessTrusted[WithOptions]`, `UNUserNotificationCenter`, `AVCaptureDevice`, `CGPreflight/CGRequestScreenCaptureAccess`, `CLLocationManager`, `SecItemCopyMatching`), the `@MainActor` `LocationAuthorizationCoordinator`, and `KeychainPermissionLedger`. A SwiftUI view consumes it via `.task` / `scenePhase` refresh; iOS has no AX, Apple Events or screen-capture preflight, so a port there keeps only notifications, location, microphone and keychain.
- **Compose**: Start from `ContextCompat.checkSelfPermission` for status and `ActivityResultContracts.RequestPermission` for requests, wrapped in a `suspend` API with `kotlinx.coroutines`. Android has no Automation or Accessibility-trust equivalents (Accessibility services are enabled in Settings, checked via `AccessibilityManager`); `shouldShowRequestPermissionRationale` is the closest signal to "undetermined vs. denied". The ledger maps to `DataStore` preferences.
- **React/Web**: Start from `navigator.permissions.query` (states `granted`/`denied`/`prompt` map directly to the tri-state) and `Notification.requestPermission`, `navigator.mediaDevices.getUserMedia`, `getDisplayMedia`, `navigator.geolocation`. There is no Automation, Accessibility or keychain analogue; screen capture has no persistent grant. A ledger maps to `localStorage`.
- **AppKit / UIKit**: Same frameworks as the source; AppKit is only needed to open `settingsPaneURL` via `NSWorkspace.shared.open` and to resolve bundle ids for `explanation(namingAutomationTarget:)` via `NSWorkspace.urlForApplication(withBundleIdentifier:)`. UIKit opens `UIApplication.openSettingsURLString` instead of per-pane URLs.
- **WinUI 3**: Model `Permission` as a C# `record` hierarchy or enum plus payload, and `PermissionStatus` as an enum; expose `Task<PermissionStatus> StatusAsync(Permission)` / `RequestAsync(Permission)` on an `IPermissionChecking` interface. Status sources: `Windows.Devices.Geolocation.Geolocator.RequestAccessAsync` (returns `GeolocationAccessStatus` Allowed/Denied/Unspecified), `Windows.Media.Capture.AppCapability.Create("microphone").CheckAccess()` / `RequestAccessAsync()`, `Windows.UI.Notifications.ToastNotificationManager.CreateToastNotifier().Setting`, `Windows.Graphics.Capture.GraphicsCaptureAccess.RequestAccessAsync`. Windows has no Apple Events or Accessibility-trust gate (UI Automation is unrestricted), so those cases have no equivalent. The keychain case maps to `Windows.Security.Credentials.PasswordVault`, which raises no per-item dialog, so the ledger becomes unnecessary; if kept, store it in `Windows.Storage.ApplicationData.Current.LocalSettings`. Settings panes open with `Launcher.LaunchUriAsync(new Uri("ms-settings:privacy-location"))` etc. Replace the GCD hop with `Task.Run` and the location waiter list with a shared `TaskCompletionSource` plus `Task.WhenAny(tcs.Task, Task.Delay(TimeSpan.FromSeconds(120)))`; a UI layer surfaces state via `INotifyPropertyChanged`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Permissions/` |

## Design Decisions

**Decision**: Tri-state status with `undetermined` distinct from `denied`.
**Rationale**: Without it a granted Automation permission would read "Not Granted" whenever the target app is quit, and a never-requested permission would read as refused (`PermissionStatus` doc comment).
**Approved**: pending

**Decision**: Blocking probes (Apple Events, first keychain read) run on a GCD global queue.
**Rationale**: They block until the user dismisses a dialog; Apple's header warns against calling them on a thread that cannot block, and a Swift cooperative thread is such a thread.
**Approved**: pending

**Decision**: Only `authorizedAlways` counts as a location grant; when-in-use reads `denied`.
**Rationale**: The consuming daemon reads location while no app is in use; reporting `denied` makes the presenter fall back to the Settings pane, since Always authorization will not re-prompt once any decision exists.
**Approved**: pending

**Decision**: One `@MainActor` location coordinator with shared waiters and a 120-second timeout.
**Rationale**: A fresh manager can answer `notDetermined` before syncing; delegate callbacks arrive on the creating thread's run loop; concurrent callers must share one prompt; the timeout stops an undecided or never-shown prompt from hanging a caller forever.
**Approved**: pending

**Decision**: Keychain status comes from a ledger of past reads, never from a probe.
**Rationale**: The two candidate oracles contradict each other on the same item, and the panel redraws on every activation, so a probe that could raise the ACL dialog would raise it repeatedly (`KeychainPermissionLedger` doc comment).
**Approved**: pending

**Decision**: The package stays Foundation-only; settings panes are URL data and Automation target names are resolved by the caller.
**Rationale**: The target must link into a daemon without AppKit, so `NSWorkspace` work lives in the UI layer.
**Approved**: pending

**Decision**: The accessibility status re-calls `AXIsProcessTrusted` rather than delegating to CoreMacOS.
**Rationale**: CoreMacOS pulls in AppKit; the OS primitive is not owned knowledge, so the two wrappers cannot meaningfully diverge.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [platform-permissions](agenticdevelopercookbook://compliance/platform-compliance#platform-permissions) | passed | Platform Compliance |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy And Data |

`separation-of-concerns` passes because the pure model (`Permission`, `PermissionStatus`), the protocol (`PermissionChecking`), the injectable probe (`AutomationProbing`) and the system conformance are separate, and UI concerns (opening panes, naming apps) are left to callers. `unit-test-coverage` is partial: the Automation, notification and location mappings and the metadata are unit-tested, but `captureStatus`, `keychainStatus` and `KeychainPermissionLedger` have no tests in the given suites, and the live system calls are runtime-only. `explicit-error-handling` is partial because `request(.notifications)` discards the thrown authorization error and the raw keychain `OSStatus` is collapsed to a tri-state. `platform-permissions` passes because each permission is requested only on an explicit `request(_:)` call and `status(_:)` never prompts. `timeout-handling` is partial: location requests time out after 120 seconds, but the Automation and keychain dialogs block with no timeout. `data-integrity` is partial because of keychain-ledger-key-collision, where distinct service names can share one ledger record. `data-minimization` passes because keychain bytes are discarded after the read and the ledger stores only a grant string.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
