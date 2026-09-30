<!-- leaf: implement-window-management/window-manager · source: window-management-window-manager.md -->

# WindowManager

## Overview

`WindowManager` (in `WindowManager.swift`) is the top-level coordinator for the
toolkit's macOS window infrastructure. It owns:

- `frames`, a `WindowFrameManager` that persists window frames and visibility
  and reacts to screen changes (specified by the frame-manager and
  ScreenManager
  recipes);
- `registry`, a `WindowRegistry` that looks up live `SingleWindowController`s by
  `windowID` through weak references;
- the launch-restore pass (`registerRestorable(id:make:)`, `restoreOnLaunch()`,
  `reopenRecentsOnLaunch()`);
- document recents recording (`windowDidInteract(_:kind:)`) and the mirror of
  `UserSettings.recentWindowsCount` into AppKit's recent-documents limit;
- an app-termination latch (`isTerminating`) that lets
  SingleWindowController
  tell a user close from a quit close.

The recipe also covers the persistence layer it is built on: the
`WindowStateStorage` protocol, its two implementations
(`SettingsStoreWindowStateStorage`, the default, and
`UserDefaultsWindowStateStorage`), the `WindowStateNamespace` key prefix that
lets two copies of one app keep separate layouts, and the `WindowScreenshot`
own-window capture utility that lives in the same folder.

Production code uses `WindowManager.shared`; tests construct an isolated
instance with a mock `ScreenProvider`, in-memory storage and an isolated
`ScreenManager`.

