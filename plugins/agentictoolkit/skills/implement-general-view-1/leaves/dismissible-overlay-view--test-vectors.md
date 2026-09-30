<!-- leaf: implement-general-view-1/dismissible-overlay-view--test-vectors · source: dismissible-overlay-view.md -->

# DismissibleOverlayView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| dismissible-overlay-001 | main-actor-isolation | Attempt to call `init` or any public method from a non-main-actor context | Code does not compile (Swift concurrency checker rejects the call) |
| dismissible-overlay-002 | coder-init | `DismissibleOverlayView(coder:)` invoked (e.g. via nib/storyboard unarchiving) | Process traps with a fatal error |
| dismissible-overlay-003 | auto-layout-participation | Inspect a freshly constructed instance and its backdrop | `translatesAutoresizingMaskIntoConstraints == false` on both self and the backdrop; `wantsLayer == true` on self |
| dismissible-overlay-004 | blurred-backdrop | Inspect the backdrop after construction | An `NSVisualEffectView` subview exists with `blendingMode == .withinWindow` and `state == .active` |
| dismissible-overlay-005 | backdrop-subview-order | Construct a subclass that adds one content subview after calling `super.init` | `subviews.first` is the backdrop; the content subview appears after it |
| dismissible-overlay-006 | backdrop-material-default | `DismissibleOverlayView()` (no `material` argument) | Backdrop's `material == .hudWindow` |
| dismissible-overlay-007 | backdrop-material-override | `DismissibleOverlayView(material: .sidebar)` | Backdrop's `material == .sidebar` |
| dismissible-overlay-008 | host-coverage | `present(in: host)` | Overlay is a subview of `host`, with top/leading/trailing/bottom anchors each constrained equal to the matching host anchor |
| dismissible-overlay-009 | present-layout-order | Call `present(in: host)`, then synchronously (before the next run-loop turn) inspect `host`'s subview layout and the overlay's `frame` | `host`'s subtree is already laid out and the overlay's `frame` already reflects its final host-pinned size at the moment `present(in:)` returns, before any animation frame renders |
| dismissible-overlay-010 | present-fade | Call `present(in: host)`, inspecting `NSAnimationContext.current.duration` from inside an injected/overridden animation hook (e.g. a test subclass that captures the context passed to `runAnimationGroup`) | `NSAnimationContext.current.duration == fadeDuration` (0.2s) while the group runs; `alphaValue` reaches `1` once the animation completes |
| dismissible-overlay-011 | dismiss-fade | Call `dismiss()` on a fully presented overlay, inspecting `NSAnimationContext.current.duration` from the same injected/overridden animation hook | `NSAnimationContext.current.duration == fadeDuration` (0.2s) while the group runs; `alphaValue` reaches `0` once the completion handler runs |
| dismissible-overlay-012 | post-fade-removal | Call `dismiss()` and wait for the fade-out animation to complete | The overlay's `superview` becomes `nil` once the completion handler runs |
| dismissible-overlay-013 | dismiss-idempotency | Call `dismiss()` twice in immediate succession | `willDismiss()` and `onDismissed` are each invoked exactly once; exactly one fade-out animation runs |
| dismissible-overlay-014 | dismissing-flag-timing | Call `dismiss()`; read `isDismissing` synchronously, before the animation completes | `isDismissing == true` immediately |
| dismissible-overlay-015 | will-dismiss-timing | Override `willDismiss()` to record a timestamp, then call `dismiss()` | The recorded timestamp precedes any change to `alphaValue` |
| dismissible-overlay-016 | dismissed-callback-timing | Set `onDismissed` to record a timestamp, then call `dismiss()` | The recorded timestamp precedes the fade-out animation's completion handler |
| dismissible-overlay-017 | default-will-dismiss | Call `dismiss()` on a plain (non-subclassed) instance | No observable side effect beyond the fade-out and removal; no crash |
| dismissible-overlay-018 | mouse-down-dismissal | Deliver a `mouseDown` event to the overlay itself, unclaimed by any subview | `dismiss()` is invoked |
| dismissible-overlay-019 | key-equivalent-subview-priority | Add a subview whose own `performKeyEquivalent` returns `true` for Return, then send a Return key event | `performKeyEquivalent` returns `true`; `dismiss()` is NOT invoked |
| dismissible-overlay-020 | escape-return-dismissal | Send a key event with `keyCode == 53` (Escape), unclaimed by any subview | `performKeyEquivalent` returns `true`; `dismiss()` is invoked |
| dismissible-overlay-020b | escape-return-dismissal | Same as above with `keyCode == 36` (Return) | Same as above |
| dismissible-overlay-020c | escape-return-dismissal | Same as above with `keyCode == 76` (keypad Enter) | Same as above |
| dismissible-overlay-021 | non-dismiss-key-equivalents | Send a key event with `keyCode == 49` (Space), unclaimed by any subview | `performKeyEquivalent` returns `false`; `dismiss()` is NOT invoked |
| dismissible-overlay-022 | key-equivalents-during-dismissal | Call `dismiss()`, then immediately send `keyCode == 53` before the fade-out completes | `performKeyEquivalent` returns `false`; `dismiss()` is not invoked a second time |
| dismissible-overlay-023 | open-subclassing | Define a subclass overriding `present(in:)`, `willDismiss()`, `mouseDown(with:)`, and `performKeyEquivalent(with:)` | Code compiles; the subclass's overrides run in place of the base implementation |
| dismissible-overlay-024 | optional-dismissed-callback | Leave `onDismissed` as `nil`, then call `dismiss()` | No crash; the fade-out animation and removal from superview still proceed |
| dismissible-overlay-025 | key-equivalent-subview-priority | Present one `DismissibleOverlayView` in `host`, then present a second instance as a subview added above the first (mirroring "a message expanded over a conversation"); send a key event with `keyCode == 53` (Escape) | `performKeyEquivalent` on the outer (first-presented) overlay returns `true` via its `super.performKeyEquivalent(with:)` call reaching the inner overlay first; only the inner (topmost) overlay's `dismiss()` is invoked, not the outer one's |

`will-dismiss-cleanup` has no test vector: it is guidance for
what a subclass author puts inside their own override, not a behavior
`DismissibleOverlayView` itself performs or can verify at the component
level (see Design Decisions).
