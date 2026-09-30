<!-- leaf: implement-general-controller/single-window-controller--part-4 · source: single-window-controller.md -->

# SingleWindowController — continued (part 4)

## Platform Notes

- **SwiftUI (`WindowGroup`/`Window` scenes)**: SwiftUI's native window scenes
  handle lazy creation and frame restoration declaratively; a SwiftUI
  equivalent would express `windowID` as a scene identifier and rely on
  `@SceneStorage`/`defaultPosition`/`defaultSize` modifiers rather than an
  imperative `NSWindowController` subclass.
- **Jetpack Compose (Desktop)**: `Window`/`DialogWindow` composables with
  `rememberWindowState` provide the closest analog to persisted frame state;
  content-hugging resize would be expressed by observing content size in a
  `SubcomposeLayout` and calling `WindowState.size = ...`.
- **React / Web**: Not applicable in the same sense — a browser tab/window is
  not directly resizable or positionable by page script in the general case;
  an Electron/Tauri shell would map this recipe onto `BrowserWindow`
  geometry-persistence APIs instead.
- **AppKit (source platform)**: This recipe is extracted directly from the
  AppKit implementation; see Behavioral Requirements above for the concrete
  API surface (`NSWindowController`, `NSWindowDelegate`, `NSPanel`). The
  content-refit machinery's private implementation names —
  `isApplyingContentFit` (reentrancy guard), `wantsRefitAfterMove` (computed
  gate), `moveRefitSettleTask` / `scheduleContentRefitAfterMove()` (the
  debounce timer), and the reused `FrameAnchors` (anchor-hold state) — are
  internal to this class; only their observable effects are asserted above.
- **WinUI 3 / Windows App SDK**: This recipe exists specifically to give the
  Windows port a `SingleWindowController`-equivalent base. A `Microsoft
  .UI.Xaml.Window` subclass would map `defaultSize`/`minSize` to
  `AppWindow.Resize`/`AppWindow.MinSize` (or `OverlappedPresenter`
  constraints), frame persistence to `ApplicationData.LocalSettings` keyed by
  `windowID`, HUD-style translucency to a `SystemBackdrop`
  (`MicaBackdrop`/`DesktopAcrylicBackdrop`) rather than raw alpha, and the
  toolbar-button mask to `AppWindowTitleBar` button-visibility properties.

## Design Decisions

**Decision**: Treat the class's own header doc comment (`super.init(windowID:)`,
`makeContentViewController()`, `makeContentView()`) as stale documentation
rather than as behavior to reproduce, since none of those symbols exist in
the implementation, which instead requires the two-argument
`init(windowID:contentViewController:)` with no content-factory override
point.
**Rationale**: source-fidelity requires describing what the code actually
does; reproducing a doc comment's invented API surface would document
behavior that cannot be exercised.
**Approved**: pending

**Decision**: Apply the toolbar button mask and HUD chrome, then run
`configureWindow(_:)`, then restore the persisted frame, and only then
assign `self` as the window's delegate.
**Rationale**: chrome installed by `configureWindow(_:)` (e.g. a toolbar)
changes how much of the window is title bar, so the frame has to be
restored onto the window only after that chrome has finished shaping it;
restoring the frame before the delegate is attached keeps the delegate from
observing the restore itself as a user-driven move/resize, which would
otherwise re-save the just-restored frame redundantly.
**Approved**: pending

**Decision**: Guard `fitWindow(toContentSize:)` with an `isApplyingContentFit`
reentrancy flag and a last-applied-fit cache (size + anchors), bailing out
when a new request repeats the last one.
**Rationale**: applying a computed frame triggers `windowDidResize`, which
could otherwise re-enter the content-refit path; the cache additionally
avoids redundant frame-setting work when content size hasn't actually
changed.
**Approved**: pending

**Decision**: Defer a scheduled move-refit indefinitely while
`NSEvent.pressedMouseButtons` reports a held button, rather than capping the
number of reschedules.
**Rationale**: refitting mid-drag would fight the user's in-progress window
placement; deferring until the drag ends (however long that takes) is
preferable to firing a refit against a frame the user hasn't finished
choosing.
**Approved**: pending

**Decision**: When `forcesWindowFront` is `false`, sink the shown window
behind the desktop and order it back (`sinkBehindDesktop()` + `orderBack(nil)`)
rather than suppressing activation alone, with `forcesWindowFront` as the
per-class opt-in that instead orders the window fully to front via
`orderFrontRegardless()`.
**Rationale**: automated tests and quiet Debug launches must not throw an
opaque, fully-drawn window over whatever the developer is doing, but the
suite still asserts `isVisible`, the restored frame, and `window.screen` —
all of which a genuinely ordered-out window would fail. Sinking behind the
desktop keeps the window real and on-screen to AppKit while invisible to the
person at the keyboard; `NSApplication.activateUnlessQuiet()` is used
separately, by `SingletonWindowController.present()`, to avoid stealing
app-wide focus.
**Approved**: pending

**Decision**: Document `SingleWindowController` as a single ingredient
covering all five of its concerns — window lifecycle/build sequencing,
frame/visibility persistence triggering, content-hugging refit with
move-debounce, HUD chrome, and the `SingletonWindowController` protocol
extension — rather than splitting each into its own ingredient recipe, even
though this gives it a larger requirement count than a typical sibling
ingredient.
**Rationale**: the five concerns are combined in one class in the source as
built, so describing them as one ingredient is source-fidelity, not a
stylistic choice; the larger count is deliberate coupling debt inherited
from the source, not a justification for scope creep in future ingredients
modeled on this one. A future split into separate ingredients — HUD chrome,
content-fit refit, and the singleton protocol extension, each referencing
this one — would need `SingleWindowController.swift` itself decomposed
first; until then this recipe carries the debt rather than hiding it.
**Approved**: pending
