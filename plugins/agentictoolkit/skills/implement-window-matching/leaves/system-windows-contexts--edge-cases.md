<!-- leaf: implement-window-matching/system-windows-contexts--edge-cases · source: window-matching-system-windows-contexts.md -->

# Window Matching System Windows Contexts

**Rules** (cite as `implement-window-matching/system-windows-contexts--edge-cases#<slug>`):

- `empty-root-directory` MUST — first launch — loadState() MUST yield no contexts and no active context; the model then seeds defaultContexts unless in …
- `missing-context-file-referenced-by-state` MUST — loadAllContexts() MUST skip it with an error log; the ID drops out of contextIDs on the next persist, and the orphan …
- `orphan-context-file-not-referenced-by-state` MUST — it MUST stay on disk untouched; the manager never reads listContextFiles().
- `active-id-points-at-a-skipped-context` MUST — activeContextID MUST keep the dangling ID and activeContext MUST return nil; switchToNextContext() then switches to the …
- `corrupt-state-json` MUST — loadState() MUST throw decodingFailed; the model sets lastError and does not seed defaults, so existing context files …
- `owning-app-mid-launch-at-load` MUST — a persisted window ID whose app has zero live windows MUST be kept, per the reconcilePersistedWindowIDs comment, so the …
- `recycled-window-id` MUST — a persisted ID now owned by another app MUST be cleared on load (reconcile-stale-recycled).
- `no-screens` MUST — NSScreen.screens empty — the parking x MUST be −30000, and no frame is captured because nothing overlaps a screen.
- `window-already-off-screen-when-its-context-is-deactivated` MUST — its saved frame MUST NOT be overwritten (frame-capture-guard).
- `persistence-failure` MUST — throwing operations MUST throw persistenceFailed with memory left ahead of disk; event operations and batch assignment …
- `lock-contention` MUST — a second process writing the same root MUST block on flock until the first finishes; there is no timeout.
- `reads-during-a-write` MUST — unlocked reads MUST see either the old or the new version of each file, because each file is replaced with an atomic …
- `assign-to-a-window-that-is-no-longer-live` MUST — the snapshot MUST still receive the ID and an empty title.
- `running-outside-an-app-bundle` MUST — the notification step MUST return before touching UNUserNotificationCenter, which the source notes crashes without a …

## Edge Cases

- **Empty root directory**: first launch — `loadState()` MUST yield no contexts and no active context; the model then seeds `defaultContexts` unless in a test environment.
- **Missing context file referenced by state**: `loadAllContexts()` MUST skip it with an error log; the ID drops out of `contextIDs` on the next persist, and the orphan never reappears.
- **Orphan context file not referenced by state**: it MUST stay on disk untouched; the manager never reads `listContextFiles()`.
- **Active ID points at a skipped context**: `activeContextID` MUST keep the dangling ID and `activeContext` MUST return `nil`; `switchToNextContext()` then switches to the first context.
- **Corrupt `state.json`**: `loadState()` MUST throw `decodingFailed`; the model sets `lastError` and does not seed defaults, so existing context files are not overwritten on that launch.
- **Empty or duplicate context names**: accepted (create-context); custom-rule auto-assignment picks the first context in display order whose name matches case-insensitively.
- **Malformed color string**: stored unchanged; the doc comment on `SystemWindowContext.color` documents the caller precondition of a `#`-prefixed hex string.
- **Owning app mid-launch at load**: a persisted window ID whose app has zero live windows MUST be kept, per the `reconcilePersistedWindowIDs` comment, so the window is not orphaned; re-matching reconciles it later.
- **Recycled window ID**: a persisted ID now owned by another app MUST be cleared on load (reconcile-stale-recycled).
- **No screens**: `NSScreen.screens` empty — the parking x MUST be −30000, and no frame is captured because nothing overlaps a screen.
- **Window already off-screen when its context is deactivated**: its saved frame MUST NOT be overwritten (frame-capture-guard).
- **Window-controller failure**: move, set-frame, and focus errors are discarded; parking failures are declared best-effort, and the open question on restore-failure-silent covers restores.
- **Persistence failure**: throwing operations MUST throw `persistenceFailed` with memory left ahead of disk; event operations and batch assignment MUST log and continue. A mid-`saveAll` failure leaves disk partially updated (the open question on save-all-not-atomic).
- **Lock contention**: a second process writing the same root MUST block on `flock` until the first finishes; there is no timeout.
- **Reads during a write**: unlocked reads MUST see either the old or the new version of each file, because each file is replaced with an atomic write; they MAY see a new context file alongside an old `state.json` mid-`saveAll`.
- **Same window assigned twice**: the batch and single assignment APIs do not reject it (the open question on assignment-window-unvalidated).
- **Assign to a window that is no longer live**: the snapshot MUST still receive the ID and an empty title.
- **Case mismatch in app names**: `markAppWindowsDormant` compares exactly, while `reMatchDormantWindowsForApp`, load-time invalidation, and custom rules compare case-insensitively.
- **Unknown rule ID on update**: silent no-op (rules-update-unknown).
- **Notification authorization denied**: no notification is posted and nothing is logged; the Reconcile window flag is still set.
- **Running outside an app bundle**: the notification step MUST return before touching `UNUserNotificationCenter`, which the source notes crashes without a bundle identifier.
- **`reconcileBehavior` set to `ignore` or `auto`**: launch reconciliation still runs the `prompt` behavior (reconcile-behavior-not-consumed).
- **Concurrent access**: the manager and model are `@MainActor`, so their operations are serialized and cannot interleave; the store is `@unchecked Sendable` with writes serialized by an inter-process `flock`. Observer events arrive on independent main-actor tasks (the open question on observer-event-ordering).
- **Cancellation and timeouts**: no operation supports cancellation or has a timeout; all work is synchronous on the calling actor except the notification authorization callback.
- **Offline or disconnected state**: not applicable; the component performs no network access.
