<!-- leaf: implement-general-2/system-permissions--edge-cases · source: system-permissions.md -->

# SystemPermissions

**Rules** (cite as `implement-general-2/system-permissions--edge-cases#<slug>`):

- `empty-automation-bundle-id` MUST (MUST) — automation(targetBundleID: "") produces the token "automation-"; the probe returns whatever non-zero status descriptor …
- `empty-keychain-service` MUST (MUST) — keychain(service: "") produces the token "keychain-" and ledger key "permission.keychain-.status"; a read with an empty …
- `target-app-not-running` MUST (MUST) — Automation status for a quit target returns -600 and reads as undetermined, never denied.
- `no-keychain-item` MUST (MUST) — request(.keychain(service:)) for a missing item returns undetermined and erases any ledger record.
- `locked-keychain-or-interaction-not-allowed` MUST (MUST) — errSecInteractionNotAllowed maps to denied and is recorded in the ledger as "denied", even though the cause may be …
- `ledger-stale-after-revocation` MUST (MUST) — A user who later removes this app from the item's ACL still reads granted from status(_:) until the app performs a real …
- `notification-request-throws` MUST (MUST) — The thrown error is discarded; the call returns the re-read status, so the failure surfaces only as denied or …
- `location-prompt-closed-without-decision-location-services-off-or-missing-usage-description` MUST (MUST) — request(.location) returns after the 120-second timeout with the current status, typically undetermined.
- `location-read-before-the-manager-has-synced` MUST (MUST) — status(.location) can report undetermined on a freshly created coordinator; the single long-lived coordinator exists to …
- `concurrent-location-requests` MUST (MUST) — Callers arriving while undetermined join the existing waiter list and timeout; all are resumed once with the same …
- `late-delegate-callback-or-timeout-after-resume` MUST (MUST) — resumeAll returns immediately when the waiter list is empty, so no continuation is resumed twice.
- `cancellation` MUST (MUST) — None of status(_:) or request(_:) observes Swift task cancellation; a cancelled caller still waits for the system …
- `timeouts` MUST (MUST) — Only location has a timeout. The Automation probe with promptIfNeeded: true and the first keychain read block their GCD …
- `screen-capture-after-refusal` MUST (MUST) — request(.screenCapture) returns denied with no dialog; recovery is via the Settings pane.
- `invalid-pane-url-string` MUST (MUST) — settingsPaneURL traps with a precondition failure; with the fixed strings in source this does not occur.

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
