<!-- leaf: implement-window-matching/core-mac-os-system-windows · source: window-matching-core-mac-os-system-windows.md -->

# SystemWindows Engine

## Overview

The CoreMacOS `SystemWindows` engine lets a host app see and control the
windows of *other* applications on macOS. It is shared logic with no UI, made
of six source files:

- `SystemWindowControlling` — the protocol (list, move, resize, focus,
  set frame) that orchestration code depends on so it can be tested with a
  mock.
- `SystemWindowManager` — the real conformer. It enumerates windows with the
  CoreGraphics window list (no permission needed), applies an enumeration
  policy, backfills missing titles through Accessibility, and manipulates
  windows through Accessibility (`AXUIElement`).
- `SystemWindowAXHelper` — bridges a CoreGraphics window id to an
  `AXUIElement` by PID plus a title/position/size score, and wraps the AX
  attribute reads, writes and the raise action.
- `SystemWindowObserver` — watches app launch/terminate (NSWorkspace) and
  window created/destroyed/title-changed (per-app AX observers) and reports
  them to a `SystemWindowObserverDelegate`.
- `SystemWindowControlError` — the typed errors of the control operations.
- `SystemAccessibilityPermission` — the one place hosts check or prompt for
  Accessibility trust; the engine itself never checks it.

Windows are described by `SystemWindowInfo` (from `AgenticToolkitCore`):
`id` (CGWindowID, `UInt32`), `app`, `pid`, `title`, `frame` (global
top-left-origin coordinates), `display`, `isOnScreen`, `layer`, plus
`withTitle(_:)` which returns a copy with only the title replaced. Use the
engine for window-context switching, window explorers and any feature that
parks, restores or raises third-party windows.

