<!-- leaf: implement-window-management/window-frame-manager--part-4 · source: window-management-window-frame-manager.md -->

# WindowFrameManager — continued (part 4)

## Privacy

- **Data collected**: Per window id and screen set, the window's frame (top-left offset, size, relative position), a save timestamp, and the screen's display UUID, localized name, resolution and main flag; per window id a visible/hidden flag.
- **Storage**: JSON blobs in `UserDefaults` under `WindowState_<id>` and Booleans under `WindowVisible_<id>`, each prefixed by `WindowStateNamespace` (default backend).
- **Transmission**: None; nothing leaves the device.
- **Retention**: A placement is kept until its screen set is unknown to `ScreenManager` and older than `maxSetAge`, then dropped at the window's next save; `resetFrame`, `resetAllFrames` and `clearSavedState` remove state on demand.

## Platform Notes

- **SwiftUI**: No SwiftUI in the source. SwiftUI's `.defaultPosition`, `.defaultSize` and scene restoration persist frames per scene but not per screen set; a SwiftUI port keeps this `@MainActor` class and reaches the underlying `NSWindow` (via an `NSViewRepresentable` window accessor) to call `restoreFrame` and `saveFrame`. `FrameCalculator` ports unchanged as pure functions on `CGRect`.
- **Compose**: Compose Desktop's `WindowState` (`position`, `size`) is the starting point, with `GraphicsEnvironment.getScreenDevices()` and `GraphicsConfiguration.bounds` / `Toolkit.getScreenInsets` for visible frames; persist with DataStore plus `kotlinx.serialization`, run on `Dispatchers.Main`. AWT coordinates are top-left-origin, so the top-left offset needs no y flip. Android phones have no free-floating windows; the math applies only to desktop and freeform modes.
- **React/Web**: Browsers expose window placement only for popups (`window.open` features, `moveTo` / `resizeTo`) and the Window Management API (`getScreenDetails()` with `availLeft` / `availTop` / `availWidth` / `availHeight`); persist with `localStorage` and `JSON.stringify`. No display UUID exists, so screen matching falls back to label and geometry; the pure frame math ports directly to TypeScript.
- **AppKit / UIKit**: Source files: `WindowFrameManager.swift` (`NSWindow.setFrame(_:display:animate:)`, `identifier`, `minSize`, `os.Logger` via `Loggable`), `FrameCalculator.swift` (pure `NSRect` math, bottom-left origin converted to top-left user coordinates), `PersistedWindowState.swift` (custom `Codable` with v1 fallback), `ScreenFingerprint.swift` (`CGDisplayCreateUUIDFromDisplayID` from `NSScreenNumber`), `ScreenInfo.swift`, `RealScreenProvider.swift` (`NSScreen.screens` / `NSScreen.main`), `ScreenMatcher.swift`, `WindowPosition.swift`. UIKit has no movable windows on iPhone; on iPad and visionOS use `UIWindowScene` geometry requests instead.
- **WinUI 3**: Start from `Microsoft.UI.Windowing.AppWindow` (`Position`, `Size`, `Move`, `Resize`, `MoveAndResize`, and the `Changed` event with `DidPositionChange` / `DidSizeChange` in place of the move/resize delegate hooks) and `DisplayArea.GetFromWindowId` / `DisplayArea.FindAll()` (`WorkArea` for the visible frame, `OuterBounds` for the resolution, `DisplayId` for identity). Windows coordinates are top-left-origin in physical pixels, so `topLeftOffset` needs no y flip but must account for DPI scaling (`XamlRoot.RasterizationScale`). Enforce `minSize` with `OverlappedPresenter` plus `PreferredMinimumWidth` / `PreferredMinimumHeight`. Keep the manager on the UI thread (`DispatcherQueue`), model `PersistedWindowState` as C# records serialised with `System.Text.Json` (a custom `JsonConverter` for the v1 fallback), and store them in `Windows.Storage.ApplicationData.Current.LocalSettings` (8 KB per value; use a `LocalFolder` file if many sets accumulate). Subscribe to display changes through `WM_DISPLAYCHANGE` / `WM_SETTINGCHANGE` or the `ScreenManager` port's event, and use `Task`/`async` only for file-based storage since the source is synchronous.

## Design Decisions

**Decision**: Placements are stored per screen set and replay an absolute top-left offset on an exact screen match.
**Rationale**: Per the `WindowPlacement` and class doc comments, replaying the literal offset means content-driven resizes "can never walk the window between launches", which the old proportional scheme did (`testContentRefitCannotDriftTopLeftAcrossRelaunches` records a clamped `proportionalY` of 1.1).
**Approved**: pending

**Decision**: A relative travel-fraction position is saved alongside the offset and used only on a non-exact match or an unknown set.
**Rationale**: A resolution change or a never-seen location makes the absolute offset meaningless; the relative position keeps a window flush to the same corner or centered.
**Approved**: pending

**Decision**: `minSize` wins over the screen size in every sizing path (`clampedLength`).
**Rationale**: Per the `clampedLength` doc comment, four paths used to spell this rule differently and returned different sizes for the same window; collapsing below `minSize` breaks the promise `minSize` makes, so the window overhangs instead.
**Approved**: pending

**Decision**: `contentHuggingFrame` chooses anchors once per gesture and returns them for the caller to pass back.
**Rationale**: Per its doc comment, no stateless nearest-edge rule is reversible under both a start and an end anchor; holding the anchor for the gesture makes "the move out the move back" (wfm-012, wfm-013).
**Approved**: pending

**Decision**: Save and restore call `ScreenManager.touchCurrentSet()` before reading `currentSetID`.
**Rationale**: AppKit repositions windows during a display reconfiguration and the resulting `windowDidMove` can reach `saveFrame` before the screen-change notification, which would otherwise file the placement under the outgoing set.
**Approved**: pending

**Decision**: A non-exact restore re-saves immediately.
**Rationale**: The delegate hooks are not wired during window loading, so without an explicit save the stale fingerprint would force relative placement on every launch instead of reaching the exact fast path.
**Approved**: pending

**Decision**: Per-window state is cached in memory, write-through.
**Rationale**: `saveFrame` fires on every move/resize tick; the cache avoids a `UserDefaults` read and JSON decode each time, under the documented sole-writer precondition.
**Approved**: pending

**Decision**: Placements are pruned with the same rule `ScreenManager` uses for sets, plus a recency grace period.
**Rationale**: Per the `saveFrame` comment, a placement survives while its set is known or it was saved recently, "so a rebuilt set list can't wipe other locations' state".
**Approved**: pending

**Decision**: Geometric centering is implemented by hand instead of `NSWindow.center()`.
**Rationale**: Per the `applyGeometricCenter` comment, `center()` places the window one-third from the top, not at the geometric center; `center()` is kept only as the no-screen fallback.
**Approved**: pending

**Decision**: v1 state is decoded through a fallback path and migrated on first restore; unrecognised blobs degrade to empty state.
**Rationale**: Per the `PersistedWindowState` decoder comment, degrading rather than throwing makes every decode call site start fresh instead of failing.
**Approved**: pending

**Decision**: `bestScreen` falls back to AppKit's window screen and main screen rather than the injected provider.
**Rationale**: This is the source's behavior when the window intersects no provided screen; it means tests with mock screens and an off-screen window can receive a real `NSScreen`. Recorded as a known quirk, not a chosen rule.
**Approved**: pending
