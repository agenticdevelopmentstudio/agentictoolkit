<!-- leaf: implement-window-management/recents--edge-cases · source: window-management-recents.md -->

# Window Management Recents

**Rules** (cite as `implement-window-management/recents--edge-cases#<slug>`):

- `missing-system-key` MUST — NSQuitAlwaysKeepsWindows absent from both the app and global domains — systemDefault MUST return false, so useSystem …
- `app-domain-override-of-the-system-key` MUST — the app writes NSQuitAlwaysKeepsWindows in its own domain — systemDefault MUST return the app-domain value, because the …
- `empty-settings-store` MUST — first launch with nothing stored — recentWindowsCount MUST read 10 and reopenOnLaunchPolicy MUST read .useSystem.
- `undecodable-stored-policy` MUST — data under "reopenOnLaunchPolicy" that is not a JSON string matching a raw value (a removed case, corrupt data) — …
- `policy-written-as-a-plain-string` MUST — a value written outside the store as a plain string (for example defaults write <bundle> reopenOnLaunchPolicy always) — …
- `zero-recent-count` MUST — recentWindowsCount = 0 (the stepper's minimum) — the mirror MUST write 0 to NSRecentDocumentsLimit; how AppKit renders …
- `negative-or-oversize-recent-count` MUST — a programmatic write of -1 or 1000 — the setting MUST store it unchanged and the mirror MUST write it unchanged; …
- `limit-takes-effect-lazily` SHOULD — per the applyRecentDocumentCountFromSettings() doc comment, AppKit honors a new limit on the next …
- `store-replaced-after-first-access` MUST — the app assigns a new UserSettings.shared after either setting was first read — the setting MUST keep observing the …
- `headless-launch` MUST — no NSApplication (for example a unit-test host) — WindowManager.reopenRecentsOnLaunch() MUST return before reading …

## Edge Cases

- **Missing system key**: `NSQuitAlwaysKeepsWindows` absent from both the app and global domains — `systemDefault` MUST return `false`, so `useSystem` MUST resolve to "do not reopen" (system-default-absent).
- **App-domain override of the system key**: the app writes `NSQuitAlwaysKeepsWindows` in its own domain — `systemDefault` MUST return the app-domain value, because the standard defaults search the app domain before the global domain; the source does not isolate the read to the global domain.
- **Empty settings store**: first launch with nothing stored — `recentWindowsCount` MUST read `10` and `reopenOnLaunchPolicy` MUST read `.useSystem`.
- **Undecodable stored policy**: data under `"reopenOnLaunchPolicy"` that is not a JSON string matching a raw value (a removed case, corrupt data) — reading MUST return `.useSystem` with no error surfaced (policy-setting-decode-fallback). The fallback is deliberate in the storage provider, and the policy degrades to the OS setting.
- **Policy written as a plain string**: a value written outside the store as a plain string (for example `defaults write <bundle> reopenOnLaunchPolicy always`) — reading MUST return `.useSystem`, because the provider reads the key as data and a plain string is not data.
- **Zero recent count**: `recentWindowsCount = 0` (the stepper's minimum) — the mirror MUST write `0` to `NSRecentDocumentsLimit`; how AppKit renders an Open Recent menu capped at zero belongs to AppKit, not to this component.
- **Negative or oversize recent count**: a programmatic write of `-1` or `1000` — the setting MUST store it unchanged and the mirror MUST write it unchanged; nothing in the source clamps it (see recent-count-range).
- **Limit takes effect lazily**: per the `applyRecentDocumentCountFromSettings()` doc comment, AppKit honors a new limit on the next `noteNewRecentDocumentURL` call, so lowering the count SHOULD NOT be expected to trim the existing Open Recent list until the next document is noted. Rationale: the mirror writes only the user default and does not ask AppKit to trim the list.
- **Store replaced after first access**: the app assigns a new `UserSettings.shared` after either setting was first read — the setting MUST keep observing the store it bound to at first access (settings-lazy-binding); hosts set `UserSettings.shared` before touching these settings, per the `UserSettings.shared` comment "Client apps should create and set this".
- **Concurrent access**: both settings are `@MainActor`, so reads and writes are serialized on the main actor and cannot interleave; `ReopenOnLaunchPolicy` values are immutable and `Sendable`; `systemDefault` is a nonisolated read of the thread-safe standard user defaults.
- **Headless launch**: no `NSApplication` (for example a unit-test host) — `WindowManager.reopenRecentsOnLaunch()` MUST return before reading `reopenOnLaunchPolicy`, so the policy is never evaluated.
- **Error states**: none of the operations can fail; every read returns a stored value or the default, and writes go through the store without a return value.
- **Offline or disconnected state**: not applicable; the component performs no network access.
- **Cancellation and timeouts**: not applicable; every operation is a synchronous user-defaults read or write, with no timeout and nothing to cancel.
