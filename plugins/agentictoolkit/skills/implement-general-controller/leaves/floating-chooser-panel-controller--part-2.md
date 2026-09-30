<!-- leaf: implement-general-controller/floating-chooser-panel-controller--part-2 · source: floating-chooser-panel-controller.md -->

# FloatingChooserPanelController — continued (part 2)

## Privacy

- **Data collected**: None — this file persists no data of its own; window
  position is recomputed on every `show()` and never saved.
- **Storage**: Not applicable — no persistence code exists in this file.
- **Transmission**: None — no networking import or call appears in this
  file.
- **Retention**: Not applicable — nothing is stored.

## Platform Notes

- **SwiftUI**: not the source form. SwiftUI's `WindowGroup`/`Scene` APIs
  have no equivalent to an on-demand, pointer-positioned, `.floating`-level
  panel that joins all Spaces, so a SwiftUI-first chooser would still wrap
  its view in an `NSHostingController` and host it inside an `NSPanel`
  managed by a controller shaped like this one, rather than a pure `Scene`.
- **Compose (Desktop)**: the nearest equivalent is an undecorated
  `androidx.compose.ui.window.Window` (`undecorated = true`,
  `alwaysOnTop = true` for floating-level behavior), positioned
  programmatically on each show; Compose for Desktop has no built-in
  equivalent to `.collectionBehavior`'s space-joining or to automatic
  dismissal on focus loss, so both would need direct AWT/Swing interop on
  top of the `Window` composable.
- **React/Web**: the nearest equivalent is a fixed-position, non-modal
  overlay (a portal styled with `position: fixed`), centered horizontally
  and offset from the top by a percentage of the viewport height; dismissal
  on focus loss has no browser-window analog for an in-page element, so it
  would be approximated with an outside-pointerdown listener and an
  `Escape` keydown handler instead of `windowDidResignKey`.
- **AppKit / UIKit**: this is the source platform, and it is AppKit-only —
  no UIKit counterpart exists (iOS has no floating, multi-Space panel
  concept). File: `FloatingChooserPanelController.swift`. It also calls
  `NSApplication.activateUnlessQuiet()`, defined in
  `NSApplication+QuietActivation.swift`.
- **WinUI 3**: the closest native shape is a secondary, undecorated
  `Microsoft.UI.Xaml.Window`/`AppWindow` with
  `TitleBar.ExtendsContentIntoTitleBar = true` (the WinUI analog of
  `fullSizeContentView`) and `IsShownInSwitchers = false`. There is no
  direct WinUI equivalent to `.floating` window level or to hiding just the
  close button of a titled window the way `standardWindowButton(_:).isHidden`
  does here — an `OverlappedPresenter` with `IsAlwaysOnTop = true` covers the
  always-on-top intent, but a truly buttonless-yet-framed title bar needs a
  fully custom `AppWindowTitleBar` (via `SetPreferredResizableRegions` /
  `ExtendsContentIntoTitleBar`) rather than hiding individual buttons.
  `.canJoinAllSpaces` has no WinUI counterpart either; Windows virtual
  desktops are a separate `VirtualDesktopManager` API and would need
  explicit pin-to-all-desktops calls to match. Positioning maps to
  `DisplayArea.GetFromWindowId`'s work area: center horizontally, offset the
  top edge by 20% of the work-area height, then call `AppWindow.Move`.
  Dismissal on focus loss maps to the `Window.Activated` event with
  `WindowActivationState.Deactivated`, checked against a
  `DismissesOnFocusLoss`-equivalent property before closing — with the same
  reentrancy guard this base class keeps as an owned boolean, since WinUI
  activation events have the same "state hasn't finished updating yet"
  hazard this file's `isDismissing` comment describes.

## Design Decisions

**Decision**: Guard reentrancy with an owned `isDismissing` boolean rather
than inferring "already closing" from window state.
**Rationale**: Closing the key window resigns key *before* the window is
ordered out, so `windowDidResignKey` re-enters mid-close; AppKit's own
window state has not finished updating at that point, so only a
controller-owned flag can distinguish a resignation that is part of this
close from one caused by the user switching away.
**Approved**: pending

**Decision**: Keep `.closable` in the style mask (which puts a close button
in the frame) and then hide the close/miniaturize/zoom buttons explicitly,
rather than omitting `.closable`.
**Rationale**: `.titled` is required for the standard frame and for
`.fullSizeContentView` to draw hosted content up into the title-bar band;
every way out of the panel already goes through `close()` via Escape,
click-away, or accepting a result, so the traffic-light buttons have
nothing left to do and are hidden rather than removed from the style mask.
**Approved**: pending

**Decision**: Call `NSApp.activateUnlessQuiet()` before `showWindow`/
`makeKeyAndOrderFront`, not after.
**Rationale**: A chooser can be opened by a system-global shortcut while
another app is frontmost; activating after taking key would let AppKit
hand key back to whichever of this app's windows held it last, closing the
just-opened panel immediately once focus-loss dismissal runs.
**Approved**: pending

**Decision**: Set `isReleasedWhenClosed = false`.
**Rationale**: `close()` runs on every dismissal, including a plain focus
loss; a chooser is expected to reopen as the same instance rather than
being rebuilt from scratch each time, so the window and its controller
must survive being closed.
**Approved**: pending

**Decision**: Position the panel relative to the screen under the mouse
pointer, not the key window's screen.
**Rationale**: The chooser can be invoked with no window of this app on
screen at all (a system-global shortcut, or an extension request), so
there may be no key window's screen to anchor to; the pointer is the one
reliable proxy for the screen the user is currently looking at.
**Approved**: pending
