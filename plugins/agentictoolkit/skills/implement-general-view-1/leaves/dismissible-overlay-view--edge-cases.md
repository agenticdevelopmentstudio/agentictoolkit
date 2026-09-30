<!-- leaf: implement-general-view-1/dismissible-overlay-view--edge-cases · source: dismissible-overlay-view.md -->

# DismissibleOverlayView

**Rules** (cite as `implement-general-view-1/dismissible-overlay-view--edge-cases#<slug>`):

- `null-empty-input` MUST (SHOULD/MUST) — onDismissed defaults to nil, and dismiss() on an instance with onDismissed == nil proceeds identically minus the …
- `boundary-values` MUST (MUST) — dismissKeyCodes is a fixed three-value set ({53, 36, 76}); a keyCode either is or is not a member — there is no partial …
- `escape-and-an-unclaimed-click-arriving-in-the-same-runloop-turn` MUST (MUST) — because isDismissing flips to true synchronously on the first call to dismiss() (per dismissing-flag-timing), whichever …
- `a-second-overlay-presented-on-top-of-the-first` MUST (MUST, per the class doc comment's "a message expanded over a conversation") — because performKeyEquivalent offers the event to subviews first (per key-equivalent-subview-priority), the topmost …

## Edge Cases

- **Null/empty input** (SHOULD/MUST): `onDismissed` defaults to `nil`, and
  `dismiss()` on an instance with `onDismissed == nil` proceeds identically
  minus the callback (MUST, per `optional-dismissed-callback`). `material`
  is a required, typed parameter with a default value (`.hudWindow`), so
  there is no null/empty case for it to guard.
- **Boundary values** (MUST): `dismissKeyCodes` is a fixed three-value set
  (`{53, 36, 76}`); a `keyCode` either is or is not a member — there is no
  partial match, range, or near-miss behavior (per
  `escape-return-dismissal` / `non-dismiss-key-equivalents`).
  `fadeDuration` is a single fixed 0.2s value with no configurable minimum
  or maximum.
- **`present(in:)` called on a momentarily zero-sized host**: because layout
  and drawing are forced before the fade starts (per
  `present-layout-order`), a host that is still zero-sized at the moment of
  the call produces a zero-sized first frame; once `host` is later given a
  real size, the overlay's own edge-pinned constraints (per `host-coverage`)
  resize it to match — nothing in source detects or defers the zero-sized
  first frame itself.
- **`dismiss()` called on an instance never passed to `present(in:)`**:
  `removeFromSuperview()` on a view with no superview is a harmless AppKit
  no-op; `willDismiss()` and `onDismissed` still fire (per
  `will-dismiss-timing` and
  `dismissed-callback-timing`) — `dismiss()` has no
  guard requiring the view to have been presented first.
- **Concurrent access**: Not applicable — the class is `@MainActor`; the
  Swift compiler confines every stored-property read/write and UI mutation
  to the main actor, so there is no path for two threads to call
  `present`/`dismiss` on the same instance simultaneously. The one
  non-isolated closure in source — `dismiss()`'s fade-out completion handler
  — is asserted back onto the main actor via `MainActor.assumeIsolated`
  before touching `self`.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no network call, database access, or file I/O; every
  operation (mutating `alphaValue`, adding/removing subviews, invoking
  closures) is synchronous, in-process, and non-throwing.
- **Offline/disconnected state**: Not applicable — no networking exists
  anywhere in this file.
- **Escape and an unclaimed click arriving in the same runloop turn**
  (MUST): because `isDismissing` flips to `true` synchronously on the first
  call to `dismiss()` (per `dismissing-flag-timing`), whichever
  gesture is processed second sees `isDismissing == true` and is a
  guaranteed no-op — this is not a race that depends on animation timing.
- **A second overlay presented on top of the first** (MUST, per the class
  doc comment's "a message expanded over a conversation"): because
  `performKeyEquivalent` offers the event to subviews first (per
  `key-equivalent-subview-priority`), the topmost overlay — being the nearer
  subview in the responder chain — is the one Escape dismisses, not the one
  underneath it; see `dismissible-overlay-025` for the two-overlay vector
  this rests on.
