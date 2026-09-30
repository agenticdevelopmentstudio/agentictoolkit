<!-- leaf: implement-general-2/system-permissions--part-3 · source: system-permissions.md -->

# SystemPermissions — continued (part 3)

**Rules** (cite as `implement-general-2/system-permissions--part-3#<slug>`):

- `keychain-status-no-access` MUST
- `keychain-request-is-read` MUST
- `keychain-request-off-cooperative-pool` MUST
- `keychain-mapping` MUST
- `keychain-request-records` MUST
- `keychain-read-discards-bytes` MUST
- `ledger-key` MUST
- `ledger-values` MUST
- `ledger-undetermined-erases` MUST
- `ledger-record-osstatus` MUST
- `ledger-forget` MUST
- `ledger-persistence` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `automationProbe` (init parameter of `SystemPermissionChecker`) | `any AutomationProbing` | `SystemAutomationProbe()` | Apple Events probe; injected so tests can stub the OSStatus |
| `Bundle.main.bundleIdentifier` | environment | host bundle id | Scopes the Notifications settings-pane URL; omitted when nil or empty |
| `UserDefaults.standard` keys `permission.keychain-<token>.status` | `String` | absent (`undetermined`) | Keychain ledger records |
| Location request timeout | constant | 120 seconds | Not configurable |
| Notification authorization options | constant | alert, sound | Not configurable |
| Host usage descriptions and entitlements | Info.plist / entitlements | — | Supplied by the host app; required by the system for location, microphone and Apple Events prompts to appear |

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

## Privacy

- **Data collected**: Grant state only. `request(.keychain(service:))` reads the item's secret bytes solely to trigger the ACL dialog and discards them (**keychain-read-discards-bytes**); the location path reads authorization status, never coordinates.
- **Storage**: The keychain ledger stores `"granted"`/`"denied"` per service in `UserDefaults.standard`; the key embeds the normalized service name. No secret is stored.
- **Transmission**: Nothing leaves the device.
- **Retention**: Ledger records persist until `forget(service:)`, `record(.undetermined, service:)`, a read returning `errSecItemNotFound`, or removal of the app's defaults.

## Platform Notes

- **SwiftUI**: Source platform is Swift on macOS, UI-free. `Permission.swift`, `PermissionStatus.swift`, `PermissionChecking.swift`, `AutomationProbing.swift` hold the pure contract; `SystemAutomationProbe.swift` wraps `AECreateDesc` + `AEDeterminePermissionToAutomateTarget`; `SystemPermissionChecker.swift` holds the per-permission calls (`AXIsProcessTrusted[WithOptions]`, `UNUserNotificationCenter`, `AVCaptureDevice`, `CGPreflight/CGRequestScreenCaptureAccess`, `CLLocationManager`, `SecItemCopyMatching`), the `@MainActor` `LocationAuthorizationCoordinator`, and `KeychainPermissionLedger`. A SwiftUI view consumes it via `.task` / `scenePhase` refresh; iOS has no AX, Apple Events or screen-capture preflight, so a port there keeps only notifications, location, microphone and keychain.
- **Compose**: Start from `ContextCompat.checkSelfPermission` for status and `ActivityResultContracts.RequestPermission` for requests, wrapped in a `suspend` API with `kotlinx.coroutines`. Android has no Automation or Accessibility-trust equivalents (Accessibility services are enabled in Settings, checked via `AccessibilityManager`); `shouldShowRequestPermissionRationale` is the closest signal to "undetermined vs. denied". The ledger maps to `DataStore` preferences.
- **React/Web**: Start from `navigator.permissions.query` (states `granted`/`denied`/`prompt` map directly to the tri-state) and `Notification.requestPermission`, `navigator.mediaDevices.getUserMedia`, `getDisplayMedia`, `navigator.geolocation`. There is no Automation, Accessibility or keychain analogue; screen capture has no persistent grant. A ledger maps to `localStorage`.
- **AppKit / UIKit**: Same frameworks as the source; AppKit is only needed to open `settingsPaneURL` via `NSWorkspace.shared.open` and to resolve bundle ids for `explanation(namingAutomationTarget:)` via `NSWorkspace.urlForApplication(withBundleIdentifier:)`. UIKit opens `UIApplication.openSettingsURLString` instead of per-pane URLs.
- **WinUI 3**: Model `Permission` as a C# `record` hierarchy or enum plus payload, and `PermissionStatus` as an enum; expose `Task<PermissionStatus> StatusAsync(Permission)` / `RequestAsync(Permission)` on an `IPermissionChecking` interface. Status sources: `Windows.Devices.Geolocation.Geolocator.RequestAccessAsync` (returns `GeolocationAccessStatus` Allowed/Denied/Unspecified), `Windows.Media.Capture.AppCapability.Create("microphone").CheckAccess()` / `RequestAccessAsync()`, `Windows.UI.Notifications.ToastNotificationManager.CreateToastNotifier().Setting`, `Windows.Graphics.Capture.GraphicsCaptureAccess.RequestAccessAsync`. Windows has no Apple Events or Accessibility-trust gate (UI Automation is unrestricted), so those cases have no equivalent. The keychain case maps to `Windows.Security.Credentials.PasswordVault`, which raises no per-item dialog, so the ledger becomes unnecessary; if kept, store it in `Windows.Storage.ApplicationData.Current.LocalSettings`. Settings panes open with `Launcher.LaunchUriAsync(new Uri("ms-settings:privacy-location"))` etc. Replace the GCD hop with `Task.Run` and the location waiter list with a shared `TaskCompletionSource` plus `Task.WhenAny(tcs.Task, Task.Delay(TimeSpan.FromSeconds(120)))`; a UI layer surfaces state via `INotifyPropertyChanged`.

