<!-- leaf: implement-general-2/system-permissions--part-2 · source: system-permissions.md -->

# SystemPermissions — continued (part 2)

**Rules** (cite as `implement-general-2/system-permissions--part-2#<slug>`):

- `permission-cases` MUST
- `permission-value-semantics` MUST
- `status-tri-state` MUST
- `undetermined-meaning` MUST
- `display-name` MUST
- `identifier-token-fixed` MUST
- `identifier-token-derived` MUST
- `system-image-name` MUST
- `explanation-default` MUST
- `explanation-automation-target` MUST
- `explanation-keychain-service` MUST
- `settings-pane-url-tcc` MUST
- `settings-pane-url-notifications` MUST
- `settings-pane-url-keychain` MUST
- `settings-pane-url-invalid-traps` MUST
- `action-title` MUST
- `action-title-all` MUST
- `checker-sendable` MUST
- `status-no-prompt` MUST
- `request-surfaces-flow` MUST
- `is-granted` MUST
- `accessibility-status` MUST
- `accessibility-request` MUST
- `notifications-mapping` MUST
- `notifications-request` MUST
- `automation-probe-flag` MUST
- `automation-mapping` MUST
- `automation-off-cooperative-pool` MUST
- `automation-probe-no-launch` MUST
- `microphone-mapping` MUST
- `microphone-request` MUST
- `screen-capture-status` MUST
- `screen-capture-request` MUST
- `location-mapping` MUST
- `location-when-in-use-denied` MUST
- `location-single-coordinator` MUST
- `location-request-settled` MUST
- `location-request-waits` MUST
- `location-request-recheck` MUST
- `location-request-timeout` MUST
- `location-shared-waiters` MUST
- `location-resume-once` MUST
- `location-delegate-ignores-undetermined` MUST

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

