<!-- leaf: implement-general-2/system-permissions--part-4 · source: system-permissions.md -->

# SystemPermissions — continued (part 4)

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
