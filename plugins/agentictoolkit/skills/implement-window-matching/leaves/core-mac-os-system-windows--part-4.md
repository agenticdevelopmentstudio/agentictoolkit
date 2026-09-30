<!-- leaf: implement-window-matching/core-mac-os-system-windows--part-4 · source: window-matching-core-mac-os-system-windows.md -->

# SystemWindows Engine — continued (part 4)

## Platform Notes

- **SwiftUI**: SwiftUI has no API for other apps' windows. A SwiftUI host keeps this engine as is and wraps the observer's delegate in an `@Observable` model on the main actor; permission UI calls `SystemAccessibilityPermission.isGranted` on scene activation and `request()` from a button.
- **Compose**: Android offers no way for an app to enumerate, move or focus another app's windows. The closest start is an `AccessibilityService` reading `getWindows()` (`AccessibilityWindowInfo` with `getTitle`, `getBoundsInScreen`, `getId`) and `TYPE_WINDOWS_CHANGED` events; move and resize have no equivalent, and window ids are direct so no matching step is needed.
- **React/Web**: A browser cannot see other applications' windows. An Electron or Node host would start from a native addon (for example `node-window-manager` or `active-win`) over the platform APIs; the matching and policy logic ports as plain TypeScript over the returned records.
- **AppKit / UIKit**: Source files are `SystemWindowManager.swift` (CoreGraphics `CGWindowListCopyWindowInfo`, `CGGetDisplaysWithPoint`, `NSScreen`, `NSRunningApplication.activate()`), `SystemWindowAXHelper.swift` (ApplicationServices `AXUIElementCreateApplication`, `AXUIElementCopyAttributeValue`, `AXValue`, `kAXRaiseAction`), `SystemWindowObserver.swift` (`AXObserverCreate` with a C callback bridged through an unretained refcon, `CFRunLoopGetMain`, `NSWorkspace` notifications, `os.Logger`), `SystemWindowControlError.swift`, `SystemWindowControlling.swift` and `SystemAccessibilityPermission.swift` (`AXIsProcessTrusted`, `AXIsProcessTrustedWithOptions` with the string key `AXTrustedCheckOptionPrompt`). The matching step exists only because `AXUIElement` exposes no CGWindowID. UIKit has no equivalent: iOS apps cannot see other apps' windows.
- **WinUI 3**: Windows App SDK's `Microsoft.UI.Windowing.AppWindow` controls only the app's own windows, so a port calls Win32 through P/Invoke or CsWin32. Enumerate with `EnumWindows`, filter with `IsWindowVisible`, `GetWindowLongPtr` (`WS_EX_TOOLWINDOW`) and `DwmGetWindowAttribute(DWMWA_CLOAKED)` instead of the layer-0 and excluded-app policy, read `GetWindowText`, `GetWindowRect` and `GetWindowThreadProcessId`, and get the app name from `System.Diagnostics.Process.GetProcessById`. An `HWND` is both id and control handle, so the AX matching step and its title/geometry score disappear. Move, resize and set-frame become one `SetWindowPos` call (atomic, unlike the source's two writes); focus becomes `ShowWindow(SW_RESTORE)` plus `SetForegroundWindow`, which Windows may refuse under its foreground lock (map that to `ActivationFailed`). Display comes from `MonitorFromPoint` with `MONITOR_DEFAULTTOPRIMARY`, matching the main-display fallback. There is no Accessibility trust gate; the equivalent failure is UIPI, which blocks a non-elevated process from moving an elevated window. Replace `SystemWindowObserver` with `SetWinEventHook` (`EVENT_OBJECT_CREATE`, `EVENT_OBJECT_DESTROY`, `EVENT_OBJECT_NAMECHANGE`, `WINEVENT_OUTOFCONTEXT`) or UI Automation (`Automation.AddAutomationEventHandler` with `WindowPattern.WindowOpenedEvent`), and app launch and exit with a `ManagementEventWatcher` on `Win32_ProcessStartTrace`/`Win32_ProcessStopTrace` or `Process.Exited`. Keep the observer on the UI thread through `DispatcherQueue`, expose windows as an `ObservableCollection<SystemWindowInfo>` with `INotifyPropertyChanged` where a view binds them, turn the delegate into C# events, and replace the `asyncAfter` delays with `await Task.Delay`.

## Design Decisions

**Decision**: Enumerate with the CoreGraphics window list and manipulate through Accessibility.
**Rationale**: Per the `SystemWindowManager` doc comment, the window list needs no permission and gives ids and PIDs, while move, resize and focus need Accessibility; the split keeps listing available to hosts without trust.
**Approved**: pending

**Decision**: Bridge a window id to an `AXUIElement` by PID plus a weighted title/position/size score, with title weighted 10 over geometry 5 and 3 and score 0 rejected.
**Rationale**: `AXUIElement` has no constructor from a CGWindowID; per the `bestMatch` comment a title match must dominate a geometry match, and two windows sharing both title and frame are inherently ambiguous, so the first wins.
**Approved**: pending

**Decision**: Geometry comparisons use a tolerance of strictly less than 2 points.
**Rationale**: The source's comments cite rounding differences between CoreGraphics bounds and AX geometry.
**Approved**: pending

**Decision**: Backfill empty titles through Accessibility, batched once per PID, taking a single-window app's title regardless of frame and refusing ambiguous frame matches.
**Rationale**: The window list omits titles without Screen Recording permission; per the `axTitle(forFrame:in:)` comment, an empty title is better than the wrong window's, and the single-window rule is what gives minimized windows a title.
**Approved**: pending

**Decision**: `focus` unparks a window by fixing only X, and visibility is tested on X alone.
**Rationale**: Parking moves windows far left while keeping Y; per the `isOnScreenHorizontally` comment, testing X avoids comparing CoreGraphics top-left Y with AppKit bottom-left screen Y.
**Approved**: pending

**Decision**: The engine is permission-agnostic; `SystemAccessibilityPermission` is separate and `request()` passes the prompt option as a string literal.
**Rationale**: Per its doc comment the UI decides when to check and prompt, and the SDK's `kAXTrustedCheckOptionPrompt` global is not concurrency-safe to reference under strict concurrency.
**Approved**: pending

**Decision**: `windowInfo(from:)` is shared by enumeration and the helper's lookup.
**Rationale**: Per its doc comment the AX path previously hardcoded the main display; one parser keeps fields and `display` identical on both paths.
**Approved**: pending

**Decision**: The window-created handler captures its baseline immediately, scoped to the owning PID, and waits 0.5 s; app launch waits 1.0 s.
**Rationale**: Per the `handleWindowCreated` comment, reading the baseline inside the delayed block races a synchronous destroy handler's refresh (TOCTOU) and would hide the new window; the delays let titles and windows settle.
**Approved**: pending

**Decision**: The observer is `@unchecked Sendable` with main-run-loop confinement and passes itself to AX callbacks as an unretained refcon.
**Rationale**: `AXObserverCreate` needs a C function pointer; confinement to the main run loop, documented on the type, is what makes the unchecked conformance sound, and `deinit` stops observation before the refcon could dangle.
**Approved**: pending
