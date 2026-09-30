<!-- leaf: implement-window-management/window-frame-manager · source: window-management-window-frame-manager.md -->

# WindowFrameManager

## Overview

`WindowFrameManager` (in `WindowFrameManager.swift`, with its helpers
`FrameCalculator`, `FrameAnchor` / `FrameAnchors`, `PersistedWindowState`,
`WindowPlacement`, `LegacyPersistedWindowState`, `ScreenFingerprint`,
`ScreenInfo` / `ScreenProvider`, `RealScreenInfo` / `RealScreenProvider`,
`ScreenMatcher` and `WindowPosition`) is the toolkit's window-frame
persistence service on macOS. It:

- holds a registry of `WindowSpec`s keyed by window id (default size, minimum
  size, default position, and whether frame and visibility persist);
- restores a window's frame on first show from the placement saved for the
  current screen set, or applies the spec's default position;
- saves a window's frame on every move or resize as a `WindowPlacement` keyed
  by `ScreenManager.currentSetID`, so a laptop that docks at several desks
  remembers one position per desk;
- repositions managed windows when `ScreenManager` reports a screen change;
- persists a window's visible/hidden flag independently of its frame.

Positions are anchored at the window's **top-left** corner from the user's
point of view (x grows right, y grows **down** from the top of the screen's
visible area). Restoring in the same screen set on an exactly matching screen
replays the saved absolute offset, so content-driven resizes cannot walk the
window between launches; a relative (travel-fraction) position is used only
when the literal geometry no longer applies.

`FrameCalculator` is a pure, side-effect-free namespace of frame math that is
also used directly by content-hugging windows (`contentHuggingFrame`).

The manager is owned by `WindowManager` and reached as
`WindowManager.shared.frames`. Usage per its doc comment: register specs at
startup with `register(id:spec:)`, call `restoreFrame(for:id:)` after creating
a window, and call `saveFrame(for:id:)` on move/resize
(`SingleWindowController` does this from its delegate hooks).

