---
id: b4cfbb31-cacc-4532-97c3-03e53852e8d3
title: System Permissions
domain: agentictoolkit://cookbook/system/permissions/system-permissions
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A tri-state permission model, status/request contract, and keychain grant
  ledger for macOS system privacy permissions, safe to link into a UI-free daemon.
platforms:
- swift
- macos
tags:
- permissions
- async
depends-on: []
related:
- agentictoolkit://cookbook/system/permissions/permission-row-view
- agentictoolkit://cookbook/system/permissions/permissions-panel-view
references:
- https://developer.apple.com/documentation/coreservices/1446026-aedeterminepermissiontoautomatetarget
approved-by: ''
approved-date: ''
---

# System Permissions

## Overview

This is the platform-free (UI-framework-free, daemon-linkable) permissions
layer of the toolkit, covering the operating system's per-permission privacy grants. It
consists of:

- a permission model — a set of the operating-system privacy grants a host app may
  need (accessibility, notifications, automation targeting a bundle
  identifier, location, microphone, screen capture, keychain access to a
  named service) with per-case metadata: a display name, a stable
  identifier token, an icon name, an explanation, a settings-pane
  location, and an action title.
- a status value — the tri-state result granted / denied / undetermined.
- a status-checking contract — an operation that reads status without
  prompting, and an operation that surfaces the system's own request
  flow, plus a granted-check convenience.
- a production status checker — the real conformance over the underlying
  platform APIs, with the Apple Events probe injected as a separate
  dependency.
- a keychain grant ledger — a persisted record of what the app last
  learned about reading a given keychain item, because the platform offers no
  way to simply ask.

Use it wherever an app or daemon has to show or obtain a privacy grant;
the UI that renders it lives in
[Permission Row View](agentictoolkit://cookbook/system/permissions/permission-row-view)
and
[Permissions Panel View](agentictoolkit://cookbook/system/permissions/permissions-panel-view).

## Behavioral Requirements

### Data shapes

- **permission-cases**: The permission model MUST have exactly seven
  cases: accessibility, notifications, automation (carrying a target
  bundle identifier), location, microphone, screen capture, and keychain
  (carrying a service name).
- **permission-value-semantics**: The permission model MUST support
  equality and hashing and MUST be safe to use across concurrent
  contexts; two automation values with different target bundle
  identifiers, or two keychain values with different service names, MUST
  be unequal (each is a distinct grant).
- **status-tri-state**: The status value MUST have exactly three cases —
  granted, denied, and undetermined — MUST support equality comparison,
  and MUST be safe to use across concurrent contexts.
- **undetermined-meaning**: undetermined MUST mean "cannot prove granted
  or denied" (never asked, target not running, no keychain item,
  timeout), and MUST NOT be used for a known refusal.

### Permission metadata

- **display-name**: The display-name property MUST return
  `"Accessibility"`, `"Notifications"`, `"Automation"`, `"Location"`,
  `"Microphone"`, `"Screen Capture"` and `"Keychain"` for the seven cases
  respectively, ignoring any carried value.
- **identifier-token-fixed**: The identifier-token property MUST return
  `"accessibility"`, `"notifications"`, `"location"`, `"microphone"` and
  `"screen-capture"` for the five cases with no carried value.
- **identifier-token-derived**: For the automation and keychain cases,
  the identifier-token property MUST be the prefix `"automation-"` or
  `"keychain-"` followed by the carried string lowercased, split on every
  non-alphanumeric character, with empty pieces dropped, and joined with
  `"-"`.
- **icon-name**: The icon-name property MUST return the icon identifiers
  `"hand.raised"`, `"bell.badge"`, `"gearshape.2"`, `"location"`, `"mic"`,
  `"display"` and `"key.fill"` for the seven cases respectively.
- **explanation-default**: The explanation property MUST equal the
  explanation-with-resolved-name operation called with the identity
  function, so an automation target is named by its raw bundle
  identifier.
- **explanation-automation-target**: For the automation case, the
  explanation-with-resolved-name operation MUST call the supplied naming
  function with the bundle identifier and embed its result in `"Needed to
  find, raise and open windows in <name>."`
- **explanation-keychain-service**: For the keychain case, the
  explanation MUST embed the service name in curly double quotes
  (U+201C, U+201D), so two services yield two different sentences.
- **settings-pane-url-tcc**: The settings-pane-location property MUST
  return the `x-apple.systempreferences:com.apple.preference.security?Privacy_<Pane>`
  location for accessibility (`Privacy_Accessibility`), automation
  (`Privacy_Automation`, one location for every target), location
  (`Privacy_LocationServices`), microphone (`Privacy_Microphone`) and
  screen capture (`Privacy_ScreenCapture`).
- **settings-pane-url-notifications**: For notifications, the
  settings-pane-location property MUST be
  `x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=<bundle id>`
  when the host has a non-empty bundle identifier, and the same location
  without the `?id=` query otherwise.
- **settings-pane-url-keychain**: For the keychain case, the
  settings-pane-location property MUST be absent, because keychain access
  is not gated by this settings mechanism and the system settings app
  lists no pane for it.
- **settings-pane-url-invalid-traps**: If a pane location string fails to
  parse as a URL, the settings-pane-location property MUST terminate the
  process with a precondition failure naming the string rather than
  return an absent value.
- **action-title**: The action-title property MUST be `"Allow…"` (with
  U+2026) when the permission has no settings pane, and `"Open Settings"`
  otherwise.
- **action-title-all**: The full list of action titles MUST list exactly
  `["Open Settings", "Allow…"]` so a caller can size a control to the
  widest title.

### Status-checking contract

- **checker-concurrency-safety**: The status-checking contract and the
  probe contract MUST be safe to use from any concurrent context; the
  production status checker and probe conformances MUST likewise be safe
  to use from any isolation domain.
- **status-no-prompt**: The status operation MUST NOT show any system
  prompt for any permission, and MUST be safe to call repeatedly (it is
  polled on every app activation by the panel).
- **request-surfaces-flow**: The request operation MUST surface the
  system's own request flow for the permission when one exists and MUST
  return the resulting status; callers MAY ignore the returned value.
- **is-granted**: The granted-check convenience MUST return true only
  when the status operation returns granted, and false for both denied
  and undetermined.

### Status mapping per permission

- **accessibility-status**: The status operation for accessibility MUST
  return granted when the process is trusted for assistive access and
  denied otherwise; it never returns undetermined.
- **accessibility-request**: The request operation for accessibility
  MUST ask for trust with its prompting option enabled, and return
  granted if trusted at that moment, else denied; it does not wait for
  the user to act in system settings.
- **notifications-mapping**: Notification authorization MUST map
  authorized, provisional and ephemeral outcomes to granted; a denied
  outcome to denied; a not-yet-determined outcome and any unknown future
  value to undetermined.
- **notifications-request**: The request operation for notifications
  MUST request authorization for alerts and sound, discard any error the
  request raises, and then return a fresh read of the notifications
  status.
- **automation-probe-flag**: The status operation for automation MUST
  call the injected probe without allowing it to prompt, and the request
  operation MUST call it with prompting allowed; both MUST forward the
  target bundle identifier unchanged.
- **automation-mapping**: An automation probe result of `noErr` (0) MUST
  map to granted, `errAEEventNotPermitted` (-1743) to denied, and every
  other value — including -1744 (consent required) and -600 (target not
  running) — to undetermined.
- **automation-probe-runs-on-dedicated-thread**: The automation probe
  MUST run on a dedicated background execution context, bridged back to
  the awaiting caller, never on the thread pool that services ordinary
  asynchronous work, because with prompting allowed it blocks until the
  user dismisses the consent dialog.
- **automation-probe-no-launch**: The production probe MUST check
  permission for the specific target bundle identifier (matching its
  event class and id as wildcards) without launching the target app, and
  MUST return the descriptor-creation status unchanged if the target
  descriptor cannot be created.
- **microphone-mapping**: Audio-capture authorization MUST map an
  authorized outcome to granted; denied and restricted outcomes to
  denied; a not-yet-determined outcome and unknown values to undetermined.
- **microphone-request**: The request operation for microphone MUST
  request audio access, ignore the returned boolean, and return a fresh
  read of the microphone status, so a restriction is distinguished from a
  first denial.
- **screen-capture-status**: The status operation for screen capture MUST
  return granted when the screen-capture preflight check passes and
  denied otherwise; it never returns undetermined, so never-asked reads
  the same as refused.
- **screen-capture-request**: The request operation for screen capture
  MUST call the system's screen-capture request and return granted or
  denied from its boolean result; after a remembered refusal the system
  shows nothing and the result is denied.
- **location-mapping**: Location authorization MUST map only an
  always-authorization outcome to granted; a when-in-use outcome, a
  denied outcome, and a restricted outcome to denied; a not-yet-determined
  outcome and unknown values to undetermined.
- **location-when-in-use-denied**: A when-in-use location grant MUST read
  as denied, not undetermined, so the caller falls back to the settings
  pane (an always-authorization decision will not re-prompt once any
  decision exists).
- **location-single-coordinator**: All location status reads and
  requests MUST go through one process-wide, serialized coordinator that
  owns a single long-lived location manager, created and receiving its
  callbacks on that same serialized context.
- **location-request-settled**: The request operation for location MUST
  request always-authorization and, when the status before the call was
  anything other than not-yet-determined, return the current status
  immediately without waiting.
- **location-request-waits**: When the status before the call was
  not-yet-determined, the request operation MUST suspend until the
  authorization changes to a decided value or the timeout fires, and
  return the status at that moment.
- **location-request-recheck**: After registering its waiter, the
  coordinator MUST re-read the authorization status and resume all
  waiters immediately if it is no longer not-yet-determined, so a
  decision landing between the request and the wait is not lost.
- **location-request-timeout**: The coordinator MUST resume all waiters
  with the then-current status 120 seconds after the first waiter
  registered, if no decision has arrived.
- **location-shared-waiters**: Concurrent request calls made while
  undetermined MUST share one system prompt and one timeout; only the
  first waiter starts the timeout.
- **location-resume-once**: Every waiter MUST be resumed exactly once:
  the coordinator reads and clears the waiter list in one serialized step
  with no suspension point, cancels the timeout, then resumes each
  waiter.
- **location-delegate-ignores-undetermined**: A callback reporting a
  not-yet-determined authorization change MUST NOT resume waiters.

### Keychain permission

- **keychain-status-no-access**: The status operation for keychain MUST
  NOT touch the keychain; it MUST return the keychain ledger's own
  recorded status for that service.
- **keychain-request-is-read**: The request operation for keychain MUST
  perform a real in-process read of a generic-password item for the
  service, requesting its data (not just attributes), matching one item,
  across both local and synchronizable keychains, so the platform raises
  its access-control dialog naming this app.
- **keychain-read-runs-on-dedicated-thread**: The keychain read MUST run
  on a dedicated background execution context, bridged back to the
  awaiting caller.
- **keychain-mapping**: A keychain read status of `errSecSuccess` MUST
  map to granted, `errSecItemNotFound` to undetermined, and every other
  status (for example `errSecAuthFailed`, `errSecUserCanceled`,
  `errSecInteractionNotAllowed`, `errSecMissingEntitlement`) to denied.
- **keychain-request-records**: The request operation for keychain MUST
  record the mapped status in the keychain ledger before returning it.
- **keychain-read-discards-bytes**: The keychain read MUST discard the
  returned item data; only the status is kept.
- **ledger-key**: The keychain ledger MUST store its record under the key
  `"permission.<identifier token of the keychain case>.status"` in the
  host's standard persisted settings store.
- **ledger-values**: The ledger MUST store the string `"granted"` or
  `"denied"`; the status-read operation MUST return granted or denied for
  those strings and undetermined for a missing key or any other value.
- **ledger-undetermined-erases**: Recording undetermined for a service
  MUST remove the key rather than store a third value.
- **ledger-record-status-code**: Recording a raw system status code for a
  service MUST map the code with the same rules as **keychain-mapping**
  and record the result.
- **ledger-forget**: Forgetting a service MUST be equivalent to recording
  undetermined for it.
- **ledger-persistence**: Ledger records MUST survive app restarts (they
  persist in the host's standard settings store) and MUST NOT be
  revalidated against the keychain on read.
- **keychain-ledger-key-collision**: Distinct keychain service names
  after normalization are a caller precondition. The identifier-token
  derivation collapses case and every run of non-alphanumeric characters,
  so services such as `"Foo Bar"` and `"foo-bar"` share one ledger key and
  overwrite each other's grant record; nothing validates or disambiguates
  service names.

## Appearance

Not applicable — this is a permissions model and system-API checker, not
a visual component.

## States

Not applicable — this is a permissions model and system-API checker, not
a visual component.

## Accessibility

Not applicable — this is a permissions model and system-API checker, not
a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| system-permissions-001 | automation-mapping | An automation probe result of 0 | granted |
| system-permissions-002 | automation-mapping | An automation probe result of -1743 | denied |
| system-permissions-003 | automation-mapping, undetermined-meaning | Automation probe results of -1744 and of -600 | undetermined for both |
| system-permissions-004 | automation-mapping | A checker with a stub probe returning -1743; read status for automation targeting bundle identifier `"com.googlecode.iterm2"` | denied |
| system-permissions-005 | automation-probe-flag | A recording stub probe; read status for automation targeting `"com.googlecode.iterm2"`, then call the request operation for the same | After the status read: the last recorded bundle identifier is `"com.googlecode.iterm2"` and prompting was not allowed; after the request: prompting was allowed. |
| system-permissions-006 | is-granted | A stub probe returning 0, then -1743, then -600, each checked via the granted-check convenience for automation targeting `"x"` | true, false, false |
| system-permissions-007 | notifications-mapping | Notification authorization outcomes of authorized, denied, and not-yet-determined | granted, denied, undetermined |
| system-permissions-008 | notifications-mapping | Notification authorization outcomes of provisional and ephemeral | granted for both |
| system-permissions-009 | location-mapping, location-when-in-use-denied | Location authorization outcomes of always-authorized, when-in-use (raw value 4), denied, restricted, not-yet-determined | granted, denied, denied, denied, undetermined |
| system-permissions-010 | microphone-mapping | Audio-capture authorization outcomes of authorized, denied, restricted, not-yet-determined | granted, denied, denied, undetermined |
| system-permissions-011 | keychain-mapping | Keychain read statuses of `errSecSuccess`, `errSecItemNotFound`, `errSecUserCanceled`, `errSecAuthFailed` | granted, undetermined, denied, denied |
| system-permissions-012 | display-name | The display name of each of the seven cases (automation targeting `"com.googlecode.iterm2"`, keychain for service `"Claude Code-credentials"`) | `"Accessibility"`, `"Notifications"`, `"Automation"`, `"Location"`, `"Microphone"`, `"Screen Capture"`, `"Keychain"` |
| system-permissions-013 | identifier-token-derived, explanation-keychain-service | Keychain permissions for services `"Claude Code-credentials"` and `"Stenographer Claude Accounts"` | Tokens `"keychain-claude-code-credentials"` and `"keychain-stenographer-claude-accounts"`; the two explanations differ, and the first contains `"Claude Code-credentials"`. |
| system-permissions-014 | identifier-token-derived | The identifier token of an automation permission targeting `"com.googlecode.iterm2"` | `"automation-com-googlecode-iterm2"` |
| system-permissions-015 | identifier-token-fixed | The identifier token of the screen-capture permission | `"screen-capture"` |
| system-permissions-016 | icon-name, explanation-default | Every permission case | A non-empty icon name and a non-empty explanation for each. |
| system-permissions-017 | settings-pane-url-tcc | The settings-pane location of accessibility, automation targeting `"com.googlecode.iterm2"`, location, microphone, screen capture | Locations ending in `...security?Privacy_Accessibility`, `...?Privacy_Automation`, `...?Privacy_LocationServices`, `...?Privacy_Microphone`, `...?Privacy_ScreenCapture` respectively. |
| system-permissions-018 | settings-pane-url-notifications | The notifications permission's settings-pane location, read in a process with a bundle identifier | Starts with `x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=` |
| system-permissions-019 | settings-pane-url-keychain, action-title | A keychain permission for service `"Claude Code-credentials"`; the accessibility permission | Keychain: no settings-pane location, action title `"Allow…"`; accessibility: action title `"Open Settings"`. |
| system-permissions-020 | action-title-all | The full list of action titles | `["Open Settings", "Allow…"]` |
| system-permissions-021 | explanation-automation-target | An automation permission targeting `"com.googlecode.iterm2"`, with its target-name resolver returning `"iTerm"` | `"Needed to find, raise and open windows in iTerm."` |
| system-permissions-022 | ledger-key, ledger-values | Record granted in the keychain ledger for service `"Claude Code-credentials"`, then read its status | The persisted key `"permission.keychain-claude-code-credentials.status"` holds `"granted"`; the read status is granted. |
| system-permissions-023 | ledger-undetermined-erases, ledger-forget | After vector 022, forget the `"Claude Code-credentials"` service | The key is removed; the read status is undetermined. |
| system-permissions-024 | ledger-record-status-code | Record the raw status code for `errSecUserCanceled` for service `"S"` | The read status for `"S"` is denied. |
| system-permissions-025 | ledger-values | The persisted key for service `"S"` holds the value `"maybe"` | The read status for `"S"` is undetermined. |
| system-permissions-026 | keychain-status-no-access | Read status for keychain service `"S"` with the ledger holding denied and no matching keychain item | Returns denied; no keychain query is issued. |
| system-permissions-027 | location-request-settled | Location authorization already denied; call the request operation | Returns denied immediately without waiting. |
| system-permissions-028 | location-request-timeout | Location authorization not-yet-determined; call the request operation; no decision arrives for 120 seconds | Resumes after 120 seconds with the then-current status (undetermined if still undecided). |

Vectors 001–012 (location arm included), 013, and 016–019 are automated.
Vectors for accessibility, screen capture, and the live
notification/microphone/keychain request flows are manual: they depend
on real TCC and keychain state that a test process cannot control.

## Edge Cases

- **Empty automation bundle id** (MUST): an automation permission
  targeting an empty bundle identifier produces the token `"automation-"`;
  the probe returns whatever non-zero status descriptor creation or the
  permission check yields, which maps to undetermined (per
  **automation-mapping**).
- **Empty keychain service** (MUST): a keychain permission for an empty
  service produces the token `"keychain-"` and ledger key
  `"permission.keychain-.status"`; a read with an empty service is issued
  as-is.
- **Target app not running** (MUST): automation status for a quit target
  returns -600 and reads as undetermined, never denied.
- **No keychain item** (MUST): the request operation for keychain, for a
  missing item, returns undetermined and erases any ledger record.
- **Locked keychain or interaction not allowed** (MUST):
  `errSecInteractionNotAllowed` maps to denied and is recorded in the
  ledger as `"denied"`, even though the cause may be transient.
- **Ledger stale after revocation** (MUST): a user who later removes this
  app from the item's access-control list still reads granted from the
  status operation until the app performs a real read and records the
  new outcome.
- **Keychain service name collision**: distinct services that normalize
  to the same token share one ledger record (see
  **keychain-ledger-key-collision**).
- **Notification request throws** (MUST): the thrown error is discarded;
  the call returns the re-read status, so the failure surfaces only as
  denied or undetermined.
- **Location prompt closed without decision, Location Services off, or
  missing usage description** (MUST): the request operation for location
  returns after the 120-second timeout with the current status,
  typically undetermined.
- **Location read before the manager has synced** (MUST): the status
  operation for location can report undetermined on a freshly created
  coordinator; the single long-lived coordinator exists to limit this.
- **Concurrent location requests** (MUST): callers arriving while
  undetermined join the existing waiter list and timeout; all are
  resumed once with the same status.
- **Late delegate callback or timeout after resume** (MUST): resuming all
  waiters returns immediately when the waiter list is empty, so no
  continuation is resumed twice.
- **Cancellation** (MUST): neither the status operation nor the request
  operation observes cancellation of the caller's own asynchronous work;
  a cancelled caller still waits for the system dialog, the background
  read, or the 120-second location timeout.
- **Timeouts** (MUST): only location has a timeout. The automation probe
  with prompting allowed, and the first keychain read, block their
  background execution context for as long as the user leaves the dialog
  open.
- **Screen capture after refusal** (MUST): the request operation for
  screen capture returns denied with no dialog; recovery is via the
  settings pane.
- **Invalid pane URL string** (MUST): the settings-pane-location property
  traps with a precondition failure; with the fixed strings in source
  this does not occur.
- **Network or offline** (not applicable): no operation performs network
  I/O; keychain synchronization across devices is handled by the
  operating system.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| automation probe (construction parameter of the production status checker) | a probe dependency | a production probe implementation | Apple Events probe; injected so tests can stub the outcome |
| host bundle identifier | environment | host bundle id | Scopes the notifications settings-pane location; omitted when absent or empty |
| persisted settings-store keys `permission.keychain-<token>.status` | a string | absent (undetermined) | Keychain ledger records |
| Location request timeout | constant | 120 seconds | Not configurable |
| Notification authorization options | constant | alert, sound | Not configurable |
| Host usage descriptions and entitlements | app manifest / entitlements | — | Supplied by the host app; required by the system for location, microphone and Apple Events prompts to appear |

## Deep Linking

Not applicable: the component registers no inbound URL route; it only
vends outbound settings-pane locations (see **settings-pane-url-tcc**),
and opening them is left to the UI layer.

## Localization

All user-facing strings are hardcoded English literals with no
localization lookup:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none) | `Accessibility`, `Notifications`, `Automation`, `Location`, `Microphone`, `Screen Capture`, `Keychain` | display name |
| (none) | `Required to discover and activate terminal windows for your sessions.` | explanation, accessibility |
| (none) | `Allows notifications when sessions start, end, or become stale.` | explanation, notifications |
| (none) | `Needed to find, raise and open windows in <name>.` | explanation, automation |
| (none) | `Records where you are and which Wi-Fi network you're on, so activity can be grouped by place.` | explanation, location |
| (none) | `Lets this app record audio from your microphone.` | explanation, microphone |
| (none) | `Lets this app read what is on your screen, to capture a still of it or record it.` | explanation, screen capture |
| (none) | `Lets this app read the "<service>" item in your keychain directly, instead of asking another tool for it.` | explanation, keychain |
| (none) | `Open Settings` | action title, when a settings pane exists |
| (none) | `Allow…` | action title, when no settings pane exists |

The identifier-token property is deliberately kept separate from the
display-name property, so the displayed copy can be reworded or
localized without breaking identifiers.

## Accessibility Options

Not applicable: the component renders nothing, so Reduce Motion, Increase
Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: no code path in the status checker or the permission
model reads a flag; every case is always available.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

- **Data collected**: Grant state only. The request operation for
  keychain reads the item's secret bytes solely to trigger the
  access-control dialog and discards them (**keychain-read-discards-bytes**);
  the location path reads authorization status, never coordinates.
- **Storage**: The keychain ledger stores `"granted"`/`"denied"` per
  service in the host's standard settings store; the key embeds the
  normalized service name. No secret is stored.
- **Transmission**: Nothing leaves the device.
- **Retention**: Ledger records persist until forgetting the service,
  recording undetermined for it, a read returning `errSecItemNotFound`,
  or removal of the app's persisted settings.

## Logging

Not applicable: the source contains no logging calls; outcomes are
reported only through the returned status value.

## Platform Notes

- **SwiftUI**: Source platform is Swift on macOS, UI-free. `Permission.swift`, `PermissionStatus.swift`, `PermissionChecking.swift`, `AutomationProbing.swift` hold the pure contract; `SystemAutomationProbe.swift` wraps `AECreateDesc` + `AEDeterminePermissionToAutomateTarget`; `SystemPermissionChecker.swift` holds the per-permission calls (`AXIsProcessTrusted[WithOptions]`, `UNUserNotificationCenter`, `AVCaptureDevice`, `CGPreflight/CGRequestScreenCaptureAccess`, `CLLocationManager`, `SecItemCopyMatching`), the `@MainActor` `LocationAuthorizationCoordinator`, and `KeychainPermissionLedger`. A SwiftUI view consumes it via `.task` / `scenePhase` refresh; iOS has no AX, Apple Events or screen-capture preflight, so a port there keeps only notifications, location, microphone and keychain.
- **Compose**: Start from `ContextCompat.checkSelfPermission` for status and `ActivityResultContracts.RequestPermission` for requests, wrapped in a `suspend` API with `kotlinx.coroutines`. Android has no Automation or Accessibility-trust equivalents (Accessibility services are enabled in Settings, checked via `AccessibilityManager`); `shouldShowRequestPermissionRationale` is the closest signal to "undetermined vs. denied". The ledger maps to `DataStore` preferences.
- **React/Web**: Start from `navigator.permissions.query` (states `granted`/`denied`/`prompt` map directly to the tri-state) and `Notification.requestPermission`, `navigator.mediaDevices.getUserMedia`, `getDisplayMedia`, `navigator.geolocation`. There is no Automation, Accessibility or keychain analogue; screen capture has no persistent grant. A ledger maps to `localStorage`.
- **AppKit / UIKit**: Same frameworks as the source; AppKit is only needed to open `settingsPaneURL` via `NSWorkspace.shared.open` and to resolve bundle ids for `explanation(namingAutomationTarget:)` via `NSWorkspace.urlForApplication(withBundleIdentifier:)`. UIKit opens `UIApplication.openSettingsURLString` instead of per-pane URLs. The icon-name property's values are SF Symbol names (`Permission.systemImageName`). The accessibility trust check passes `AXTrustedCheckOptionPrompt: true` as its prompt option (**accessibility-request**). `PermissionChecking.request(_:)`'s returned status is `@discardableResult`, so a caller may ignore it without a compiler warning (**request-surfaces-flow**).
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to system/permissions/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
