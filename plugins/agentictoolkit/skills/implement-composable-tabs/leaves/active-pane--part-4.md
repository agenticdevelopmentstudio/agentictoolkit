<!-- leaf: implement-composable-tabs/active-pane--part-4 · source: composable-tabs-active-pane.md -->

# ComposableTabsActivePane — continued (part 4)

## Platform Notes

- **SwiftUI**: There is no SwiftUI equivalent of a single, app-wide local
  `NSEvent` monitor, so the click/pointer capture still has to happen at
  whatever AppKit-hosting layer wraps the SwiftUI content. Model the tracker
  itself as a single, app-wide `ObservableObject` — mirroring
  `ComposableTabsActivePane.shared`, one instance keyed internally by window,
  not one instance per window/scene — exposed via `.environmentObject`, and
  give each pane a modifier that reads its own `nodeID` against the tracker's
  `activeNodeID(in:)` to pick `.overlay(Rectangle().strokeBorder(color, lineWidth: 2))`,
  so the stroke stays inside the edge the way the inset border does here,
  where `color` switches between the accent and hairline tokens exactly as
  `applyTheme(_:)` does.
- **Compose (Desktop)**: Compose Desktop's `Window` maps closely to `NSWindow`,
  so hold the active-pane map as a `MutableState<UUID?>` per `Window`
  (hoisted in a `CompositionLocal`, one per window scope). Use
  `Modifier.onPointerEvent(PointerEventType.Press)` for the click path and
  `Modifier.onPointerEvent(PointerEventType.Move)` gated by the equivalent
  setting for the pointer-follows path, and `Modifier.border(2.dp, if (isActive) accent else outline)`
  for the outline, matching the always-2pt, color-only distinction this file
  draws.
- **React/Web**: The web platform has effectively one window, so the
  per-window map collapses to a single ref/state value held by an
  `ActivePaneProvider` context. Attach `mousedown`/pointer-move listeners at
  the document root in the capture phase (mirroring the one local monitor
  here, instead of one listener per pane) and toggle a `data-active`
  attribute or CSS class on the pane element to switch its outline color;
  gate pointer-move-driven switching behind a user preference the same way
  `activePaneFollowsMouse` gates it here.
- **AppKit/UIKit**: This is the source platform; see
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsActivePane.swift`.
  It is macOS-only — `NSEvent` local monitors, `NSWindow.firstResponder`/
  `makeFirstResponder`, weak `NSHashTable` collections, and
  `NSWindow.didBecomeKeyNotification`/`didResignKeyNotification` all have no
  UIKit equivalent. UIKit has no local-monitor concept and (outside iPad
  multi-window) no second window competing for keyboard focus in the same
  sense; a port to iPad multi-window would need `UIGestureRecognizer`s or a
  `UIWindow.hitTest` override plus a walk up the `UIResponder.next` chain in
  place of the `NSEvent` monitor and `makeFirstResponder` walk used here.
- **WinUI 3**: Track the active pane per `Window` (WinUI 3's per-window model
  matches `NSWindow` closely) in a `Dictionary<Window, Guid>`, mutated only
  from the UI thread — WinUI is single-threaded per dispatcher, matching this
  file's `@MainActor` — and remove a window's entry when its `Window.Closed`
  event fires, mirroring how the source clears `activeByWindow` on
  `NSWindow.willCloseNotification` (see
  **close-and-highlight-changes-dispatch-through-the-main-queue** and
  **window-close-clears-active-id-silently**) rather than relying on garbage
  collection to age the entry out — `Guid` is a value type, so a
  `ConditionalWeakTable` cannot hold it directly the way the source's weak
  `NSHashTable`s hold reference types. Replace the `NSEvent` local monitor with a
  `PointerPressed` handler added at the `Window.Content` root via the
  `AddHandler` overload that takes `handledEventsToo: true`, so a click is
  still seen even if an inner control already marked it handled — the WinUI
  analogue of a monitor that "sees the events before the responder chain
  does." Gate a matching root-level `PointerMoved` handler behind a setting
  equivalent to `activePaneFollowsMouse`, and behind `Window.Activated`
  state (`WindowActivationState.Deactivated` in place of "not key") and a
  check for an open modal in place of an attached sheet. For the focus walk,
  use `FocusManager.TryMoveFocusAsync`/`Control.Focus(FocusState.Programmatic)`
  starting from the hit-tested element and walking outward through its
  `VisualTreeHelper` ancestry, mirroring `takeFocus`'s innermost-first order;
  handle `Control.LosingFocus` with `args.Cancel = true` as WinUI's
  equivalent of a responder refusing to resign, and check that flag before
  calling the WinUI equivalent of `activate` — mirroring
  **focus-refusal-blocks-mouse-moved-activation**. For the chrome, wrap each
  pane's content in a `Border BorderThickness="2"` bound to a
  `SolidColorBrush` resource that switches between the app's accent brush and
  a neutral outline brush via a view-model boolean exactly like `isActive`
  here, and inset the pane's own background `Border`/`Grid` by 2px from that
  outer `Border`'s edge to reproduce `borderInset`.

## Design Decisions

- **Decision**: Pointer movement is gated behind `activePaneFollowsMouse`,
  which defaults to `false`.
  **Rationale**: Per the source's own comment, focus that moves without being
  asked to is a preference people hold strongly in both directions, and the
  surprising answer — the keys going somewhere the user did not put them —
  is judged the wrong default.
  **Approved**: pending
- **Decision**: A click activates the hit pane directly and never itself
  calls `takeFocus`; only a pointer move calls it.
  **Rationale**: A click already carries its own focus through AppKit's
  ordinary hit-test-to-first-responder path, so calling `takeFocus` for a
  click would be redundant. A move carries no such focus of its own, so
  without an explicit call the outline could move to a pane the keyboard
  never followed into.
  **Approved**: pending
- **Decision**: For a pointer move, focus is taken before the pane is
  activated, and a refusal from the outgoing responder blocks the activation
  entirely — nothing is left half-changed.
  **Rationale**: The source notes that a text field failing validation in
  `resignFirstResponder` is AppKit's ordinary way of saying "finish this
  first"; outlining the new pane anyway would point at a pane the keyboard
  is not actually in.
  **Approved**: pending
- **Decision**: A hidden pane (for example, a collapsed split) still counts
  as "live" and still holds the active id; only removal from the window ends
  its claim.
  **Rationale**: Per the source's own comment, a collapsed split is still the
  user's pane; only a pane out of the window entirely has stopped being
  somewhere the keys can go.
  **Approved**: pending
- **Decision**: `isInActivePane(_:)` is deliberately blind to whether the
  window is key.
  **Rationale**: The source states this is deliberate: which pane the user is
  working in does not change because a settings window came forward, and a
  pane that dimmed itself every time Settings opened would be reporting the
  wrong thing exactly when the user was looking at it.
  **Approved**: pending
- **Decision**: The `NSEvent` monitor is local to the app's own windows, not
  global.
  **Rationale**: This app only needs to know about the pointer inside its own
  windows, and a local monitor sees events before the responder chain does
  without requiring the accessibility permission a global monitor would need.
  **Approved**: pending
- **Decision**: `NSWindow.willCloseNotification` handling and the
  `highlightActivePane` settings-change handling are both explicitly
  dispatched onto `DispatchQueue.main`, not `RunLoop.main`.
  **Rationale**: `RunLoop.main` enqueues only in `.default` mode, so anything
  posted while AppKit tracks a mouse-down in `.eventTracking` mode (for
  example, a checkbox being clicked) would not run until the tracking loop
  ended. `DispatchQueue.main` is drained in every mode.
  **Approved**: pending
- **Decision**: Every pane's backdrop is always outlined at a constant 2pt
  width; only the border color distinguishes the active pane.
  **Rationale**: The source states that outlining only the active pane left
  every other pane reading as an unbounded field of `windowBackground`, so
  two panes side by side would look like one pane with a seam down it. A
  constant width means clicking between panes recolors a line instead of
  moving one.
  **Approved**: pending
- **Decision**: The workspace's own backdrop plane (not the pane's fill) is
  what the active-pane border is drawn against, with the pane's fill inset
  inside it.
  **Rationale**: The source states that painting the border and the pane's
  fill as one plane put a hairline of window background between a tab and
  the pane it belongs to, all the way around; the two-plane structure keeps
  the tab reading as part of the workspace instead of something stuck on top
  of it.
  **Approved**: pending
- **Decision**: `paneWindows` and `paneViews` are weak `NSHashTable`
  collections rather than strong references.
  **Rationale**: Per the source's own comments, both are convenience lists,
  never owners; a closed window or a pane that has left its window needs to
  be able to go away without this component being told twice.
  **Approved**: pending
