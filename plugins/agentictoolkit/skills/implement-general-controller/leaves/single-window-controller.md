<!-- leaf: implement-general-controller/single-window-controller · source: single-window-controller.md -->

# SingleWindowController

## Overview

`SingleWindowController` is an `open`, `@MainActor`-isolated `NSWindowController` /
`NSWindowDelegate` base class for AppKit apps that manage exactly one live
`NSWindow` per logical `windowID`. A subclass supplies a `windowID` and a
content view controller at `init`, and may override `windowTitle`,
`defaultContentRect`, `windowStyleMask`, `minSize`, and `configureWindow(_:)`
to shape the window before it is first shown. The window itself is not built
in `init` — it is built lazily, the first time AppKit calls `loadWindow()`
(driven by the first access to `window` — typically the first `showWindow`
call), from an `NSPanel` if `windowStyleMask` includes `.utilityWindow` or
`.hudWindow`, otherwise a plain `NSWindow`.

Once built, the controller wires itself to two toolkit-wide subsystems: the
`WindowFrameManager` (via the `windowSpec` computed property that
`WindowFrameManager.swift` adds to this class in an extension), which restores
and re-saves the window's frame and visibility, and the `WindowRegistry`
(`WindowManager.shared.registry`), which tracks one live controller per
`windowID` so callers can look an open window up by ID. The controller also
supports "content-hugging" resizing through `fitWindow(toContentSize:)`, an
optional `HUDConfiguration` for translucent floating utility windows, and
conformance to `SingletonWindowController` for call sites that want a single
shared instance addressable as `Self.current`.

The class's own header doc comment shows a `Usage` example that calls
`super.init(windowID:)` with a single argument and overrides a
`makeContentViewController() -> NSViewController?` factory method (also
mentioning a `makeContentView()`). Neither of those exists anywhere in the
implementation below: the only initializer is the two-argument
`init(windowID:contentViewController:)`, and there is no content-factory
override point at all — the content view controller is a fixed, required
constructor argument (see Design Decisions for how this recipe treats the
mismatch).

