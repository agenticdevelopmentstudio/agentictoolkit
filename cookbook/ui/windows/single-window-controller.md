---
id: 3f6268b8-410d-4d3c-979c-2a9f9f1534f3
title: Single-Instance Window
domain: agentictoolkit://cookbook/ui/windows/single-window-controller
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A base window controller that lazily builds a single window from subclass
  configuration, persists its frame and visibility, and supports quiet presentation
  and HUD chrome.
platforms:
- swift
- macos
tags:
- window-controller
- frame-persistence
- hud
- singleton
depends-on: []
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
- agentictoolkit://cookbook/ui/windows/window-controller
- agentictoolkit://cookbook/ui/layout/composable-tabs/tabs-window
references: []
approved-by: ''
approved-date: ''
---

# Single-Instance Window

## Overview

This is a base class for managing exactly one live window per logical window
ID. A subclass supplies a window ID and content at construction, and may
override the window's title, default content rect, style options, minimum
size, and a configuration hook to shape the window before it is first shown.
The window itself is not built at construction — it is built lazily, the
first time the platform asks for the window to be loaded (typically driven by
the first call that shows it), as a utility-style window when the style
options request a utility or HUD appearance, otherwise a standard window.

Once built, the controller wires itself to two toolkit-wide subsystems: the
window frame manager, which restores and re-saves the window's frame and
visibility, and the window registry, which tracks one live controller per
window ID so callers can look an open window up by ID. The controller also
supports "content-hugging" resizing through a fit-to-content operation, an
optional HUD configuration for translucent floating utility windows, and
conformance to a single-instance protocol for call sites that want a single
shared instance addressable through a class-level accessor.

The class's own header doc comment shows a usage example that calls a
single-argument initializer and overrides a content-factory method (also
mentioning a second, view-returning factory method). Neither of those exists
anywhere in the implementation below: the only initializer takes both a
window ID and content, and there is no content-factory override point at all
— the content is a fixed, required constructor argument (see Design
Decisions for how this recipe treats the mismatch).

## Behavioral Requirements

- **single-thread-isolation**: The type and every one of its members MUST be
  confined to a single designated thread.
- **init-argument-storage**: Constructing the controller with a window ID and
  content MUST store both for use when the window is later built. Neither
  argument is validated for emptiness or content at construction time; an
  empty window ID is accepted and stored as-is (see **registry-registration**
  for what an empty ID means downstream).
- **no-deserialization-init**: The class MUST NOT support construction by
  deserializing an archive; that initializer MUST be unavailable (a
  compile-time error if referenced).
- **default-size**: The class MUST expose a type-level default size of
  600 × 480 (width × height) that subclasses may override to change the
  fallback window size used when no persisted frame exists.
- **forces-window-front**: The class MUST expose an overridable type-level
  flag that subclasses set to request that showing the window additionally
  bring it fully to the front (see **forces-front-ordering**) even when
  quiet presentation would otherwise keep it out of the way (see
  **quiet-presentation**).
- **window-title**: The window's title MUST be an overridable computed
  property (default empty string) that subclasses override to supply the
  window's title.
- **default-content-rect**: The default content rect MUST be an overridable
  computed property that returns a rectangle whose origin is zero and whose
  size is the type-level default size, used only when no persisted frame is
  available.
- **window-style-mask**: The window's style options MUST be an overridable
  computed property (default: titled, closable, miniaturizable, resizable)
  that subclasses override to change the window's chrome, e.g. to request a
  utility or HUD appearance.
- **min-size**: The window's minimum content size MUST be an overridable
  computed property (default 200 × 150) that subclasses override to change
  it.
- **configure-window-hook**: A configuration hook MUST be an overridable,
  no-op-by-default method called once, after the window is built and before
  it is returned from the build step, so subclasses can perform one-time
  additional window setup (toolbar items, appearance, etc.).
- **lazy-window-build**: The controller MUST NOT build its window at
  construction; it MUST build it the first time the window is loaded (i.e.,
  the first time the platform or a caller accesses it).
- **panel-selection**: Building the window MUST construct a utility-style
  window when the style options request a utility or HUD appearance, and a
  standard window otherwise.
- **window-construction**: Building the window MUST construct it with the
  default content rect as its content rect, the style options as its style,
  buffered backing, and no deferred creation.
- **title-on-build**: Building the window MUST set the built window's title
  to the overridable title property.
- **content-view-controller-on-build**: Building the window MUST set the
  built window's content to the content supplied at construction.
- **min-size-on-build**: Building the window MUST set the built window's
  minimum size to the overridable minimum-size property.
- **accessibility-identifier**: Building the window MUST assign the window
  an accessibility identifier derived by slugifying the window ID, so windows
  are addressable in UI tests. Slugification splits camelCase boundaries,
  lowercases, and joins non-alphanumeric runs with hyphens.
- **toolbar-button-mask**: Building the window MUST, when a window spec is
  registered for the window ID, mask the window's standard button visibility
  for close/miniaturize/zoom according to the spec's toolbar-buttons setting,
  hiding any button whose corresponding option is absent from that setting.
- **toolbar-button-mask-default**: Building the window MUST leave all three
  standard window buttons at their platform-default visibility when no
  window spec is registered for the window ID.
- **build-sequence**: Building the window MUST run its steps in this order,
  after constructing the window and setting its title, minimum size,
  accessibility identifier, and content: (1) assign the constructed window to
  the controller's window property; (2) apply the toolbar button mask and,
  if HUD-configured, the HUD chrome; (3) invoke the configuration hook
  exactly once; (4) ask the window frame manager to restore any persisted
  frame for the window ID and apply it to the window; (5) assign the
  controller itself as the window's delegate. Restoring the frame before
  delegate assignment (step 4 before step 5) keeps the restore from itself
  triggering move/resize bookkeeping through the delegate. Running the
  configuration hook before the frame restore (step 3 before step 4) lets
  subclass-installed chrome — a toolbar, for instance, which changes how tall
  the title bar is — finish shaping the window before geometry is restored
  onto it. The window property is assigned early (step 1), not as a final
  step: registry registration is a separate, earlier event — see
  **registry-registration**, which happens at construction, not as part of
  this sequence.
- **registry-registration**: Constructing the controller MUST register it
  with the window registry under the window ID, unconditionally, before any
  window is built — registration does not wait for the window to be built or
  shown.
- **registry-registration-empty-id**: Registration with the window registry
  MUST be a silent no-op when the window ID is empty (the registry's own
  registration guards on a non-empty ID); constructing the controller MUST
  NOT crash or otherwise special-case an empty window ID beyond that. This is
  verified in the window registry; this class supplies no additional guard
  because none is needed.
- **forces-front-ordering**: Showing the window MUST run the platform's
  standard show behavior first — which brings the window to key status and
  orders it front — and then, when the forces-front flag is set, additionally
  force the window fully to front so it is pulled above other applications'
  windows too. No explicit app-activation call is made by this method.
- **quiet-presentation**: Showing the window MUST, when the forces-front flag
  is not set, leave the window ordered by the standard show behavior alone
  and additionally sink it behind the desktop and order it back, so the
  window stays a real, laid-out, visible window — satisfying assertions on
  its visibility, its restored frame, and its screen — without appearing to
  the person at the keyboard.
- **show-window-convenience**: The class MUST expose a parameterless
  show-window convenience that forwards to the sender-taking version with no
  sender, for call sites that have no natural sender.
- **visibility-persist-on-show**: Showing the window MUST record the window
  as visible through the window frame manager when the window's spec has
  visibility persistence enabled.
- **dismiss-method**: The class MUST expose a dismiss method that closes the
  window rather than requiring callers to reach through to the underlying
  window.
- **visibility-persist-on-dismiss**: Dismissing MUST record the window as
  hidden through the window frame manager when the window's spec has
  visibility persistence enabled, mirroring the show behavior on the closing
  path.
- **is-visible**: The class MUST expose a computed visibility flag that
  reflects the underlying window's visibility, returning false when no
  window has been built yet.
- **content-fit**: The fit-to-content operation MUST resize the window's
  content area to the given size using the content-hugging frame
  calculation, which keeps one edge of the window anchored (by default
  top-left) while the opposite edges move to accommodate the new content
  size.
- **content-fit-bail**: The fit-to-content operation MUST compare the
  requested size and anchor state against the last applied fit and skip
  re-applying the frame when both are unchanged, to avoid redundant
  frame-setting work and redundant resize notifications on repeated calls
  with identical inputs.
- **fit-anchor-stability**: The fit-to-content operation MUST reuse the
  anchor point computed on the first fit for subsequent fits, rather than
  recomputing an anchor point from the window's current frame on every call,
  so the anchor edge stays stable across a sequence of content-size changes.
- **reentrant-fit-guard**: The fit-to-content operation MUST guard its own
  frame application so that a resize callback triggered by that very frame
  change does not re-enter the content-refit machinery.
- **content-size-provider**: The class MUST expose a settable
  content-size-provider callback that, when set, supplies the desired
  content size for the refit operation to apply via the fit-to-content
  operation.
- **content-refit-gate**: The refit operation MUST be a no-op when the
  content-size provider is unset, and otherwise MUST call the provider and
  pass its result to the fit-to-content operation.
- **move-refit-debounce**: After a window move, the controller MUST debounce
  refitting by waiting 200 milliseconds before performing the refit,
  canceling and restarting that wait on every subsequent move so only the
  most recently moved-to position's timer ever fires.
- **refit-drag-deferral**: The debounced refit MUST check whether a mouse
  button is currently held (the user is still dragging the window) and, if
  so, reschedule itself rather than performing the refit immediately, so a
  refit does not fight an in-progress drag.
- **move-triggers-refit**: A window-move callback MUST schedule a refit (see
  **move-refit-debounce**) only when the content-size provider is set; with
  no provider set, a move MUST NOT schedule any refit work.
- **frame-persist-on-move**: A window-move callback MUST persist the
  window's new frame through the window frame manager when the window's spec
  has frame persistence enabled.
- **frame-persist-on-resize**: A window-resize callback MUST persist the
  window's new frame through the window frame manager when the window's spec
  has frame persistence enabled, mirroring the move-triggered save.
- **resize-refit-guard**: A window-resize callback MUST skip triggering the
  refit operation when the resize was caused by the controller's own
  fit-to-content call (see **reentrant-fit-guard**), so the refit path does
  not recursively re-trigger itself.
- **visibility-persist-on-close**: A window-will-close callback MUST record
  the window as hidden through the window frame manager when the window's
  spec has visibility persistence enabled, so closing the window via its own
  close button (not just via dismiss) is captured.
- **visibility-restore**: The visibility-restore operation MUST show the
  window when the window's spec has visibility persistence enabled and the
  persisted visibility state is true; otherwise it MUST leave the window
  unshown.
- **hud-configuration**: The class MUST define a nested HUD-configuration
  value with a floating flag (default true) and a transparency value
  (default 1.0), captured by the HUD-configuration operation.
- **hud-chrome-opt-in**: The HUD-configuration operation MUST be the only
  entry point that applies HUD-specific chrome (background translucency and,
  when floating, a floating window level); a window that never calls it
  MUST render with ordinary opaque, non-floating chrome.
- **hud-transparency-floor**: The HUD-configuration operation and the
  set-transparency operation MUST clamp the given transparency value to the
  range 0.3 to 1.0 before applying it as the window's opacity, so a HUD
  window can never be set fully transparent (invisible but still clickable).
- **set-floating**: The set-floating operation MUST set the window's level
  to floating when true, and to normal when false.
- **set-transparency**: The set-transparency operation MUST set the window's
  opacity (not its background color) to the given value clamped per
  **hud-transparency-floor**, independent of the floating level set by the
  set-floating operation.
- **singleton-protocol-conformance**: A subclass that adopts the
  single-instance protocol MUST get its ensure-current, present, and is-open
  operations from the protocol extension without additional implementation,
  provided it supplies the class-level current-instance accessor and a
  shared-instance factory.
- **singleton-ensure-current**: The ensure-current operation MUST create the
  shared instance via the shared-instance factory and assign it to the
  current-instance accessor only when no current instance exists, and MUST
  leave an existing current instance untouched otherwise (i.e., only one
  shared instance is created per process, reused across calls).
- **singleton-present**: The present operation MUST call the ensure-current
  operation and then call the parameterless show-window operation on the
  resulting instance.
- **singleton-is-open**: The is-open operation MUST return false when no
  current instance exists, and otherwise MUST return the current instance's
  visibility flag.

## Appearance

| Element | Value | Source |
|---|---|---|
| Default window size | 600 × 480 pt | the type-level default size |
| Default minimum size | 200 × 150 pt | the minimum-size property |
| Default style mask | titled, closable, miniaturizable, resizable | the style-options default |
| HUD style mask | requests a utility or HUD appearance | subclass override, detected by the build step's window-class check |
| HUD transparency | subclass-supplied value, clamped to 0.3-1.0 | the HUD-configuration operation |
| Background color | Not applicable — the base class sets no explicit background color; a HUD window's translucency is the only appearance concern this class owns, and it is described above. Any theme-token background belongs to the hosted content, not to this class. | this class; contrast with content-level theme observers |

## States

| State | Behavior | Source |
|---|---|---|
| Not yet built (window never accessed) | No window exists; the visibility flag returns false; the registry already has an entry for the window ID from construction | window building is lazy; the visibility flag; **registry-registration** |
| Built, hidden | Window exists, but not on screen | default post-build state before showing |
| Built, visible | Window on screen; frame/visibility persisted on further move/resize/close when opted in | showing the window; the delegate callbacks |
| Built, HUD-configured | Translucent, optionally floating, chrome applied once via the HUD-configuration operation | the HUD-configuration operation |
| Applying a content fit | Concurrent resize-driven refit suppressed | the fit-to-content operation, the resize callback, **reentrant-fit-guard** |
| Awaiting move-settle | A debounced refit is pending; refit deferred while mouse button held | **move-refit-debounce**, **refit-drag-deferral** |
| Pressed | Not applicable — this class manages a window shell, not a pressable control; press-state feedback belongs to whatever control the hosted content renders. | this class has no control-rendering code |
| Disabled | Not applicable — a window controller has no enabled/disabled state of its own; if the app wants to disable interaction it disables specific controls in the content. | same |
| Focused | Not applicable at this layer beyond ordinary platform key-window handling, which this class does not customize. | this class overrides no key-window/first-responder logic |
| Loading | Not applicable — window construction is synchronous; there is no asynchronous loading state to represent. | the build step |

## Accessibility

- **Role**: Not applicable beyond the platform's own default window role; the
  class does not set or alter it.
- **Label**: The window's accessibility identifier (not label) is set
  explicitly, to a slug of the window ID, when building the window, so UI
  tests can address the window by a stable, derived identifier. The window's
  human-facing title (used as its accessible name by the platform's own
  window accessibility support) is the title property, supplied by the
  subclass.
- **Announcements**: Not applicable — the base class performs no
  accessibility-announcement calls of its own; window appearance/disappearance
  announcements are handled by the platform's standard window-server
  behavior, not by this class.
- **Keyboard navigation**: Not applicable at this layer — key-view loops and
  first-responder handling belong to the hosted content, not to this class,
  which never overrides key handling.
- **Touch target size**: Not applicable — this class manages a window, not a
  tappable control; standard title-bar buttons keep the platform's own
  built-in target sizes, which this class does not adjust (it only
  hides/shows the standard buttons, never resizes them).

## Conformance Test Vectors

| ID | Requirement | Given | When | Then |
|---|---|---|---|---|
| single-window-controller-001 | single-thread-isolation | any instance | a method is invoked while already confined to the single designated thread | the assertion succeeds; no isolation violation occurs |
| single-window-controller-002 | init-argument-storage | a window ID and content | the controller is constructed | both are stored for later use when the window is built, with no validation of the window ID's emptiness |
| single-window-controller-003 | no-deserialization-init | any | archive-based construction is invoked | a fatal/unavailable-API error occurs, not a working instance |
| single-window-controller-004 | default-size | a subclass overriding the default size | no persisted frame exists | building the window uses the overridden size |
| single-window-controller-005 | forces-window-front, forces-front-ordering | a subclass with the forces-front flag set | the window is shown | the standard show behavior runs first, then the window is additionally forced fully to front, pulling it above other applications' windows |
| single-window-controller-006 | window-title | a subclass overriding the title property | the window is built | the built window's title equals the overridden value |
| single-window-controller-007 | default-content-rect | a subclass overriding the default content rect, no persisted frame | the window is built | the window is created with the overridden rect |
| single-window-controller-008 | window-style-mask | a subclass overriding the style options to request a HUD appearance | the window is built | a utility-style window is constructed instead of a standard window |
| single-window-controller-009 | min-size | a subclass overriding the minimum size | the window is built | the built window's minimum size equals the overridden value |
| single-window-controller-010 | configure-window-hook | a subclass overriding the configuration hook | the window is built | the override is invoked exactly once with the fully assembled window |
| single-window-controller-011 | lazy-window-build | a freshly constructed controller | construction completes but the window is not accessed | no window has been constructed |
| single-window-controller-012 | panel-selection | the style options request a utility appearance | the window is built | the constructed object is a utility-style window |
| single-window-controller-013 | window-construction | default configuration | the window is built | the window's content rect, style options, backing, and defer flag match the documented values |
| single-window-controller-014 | title-on-build | the title property overridden to `"Example"` | the window is built | the window's title equals `"Example"` |
| single-window-controller-015 | content-view-controller-on-build | content supplied at construction | the window is built | the window's content is that instance |
| single-window-controller-016 | min-size-on-build | the minimum-size property overridden | the window is built | the window's minimum size equals the overridden value |
| single-window-controller-017 | accessibility-identifier | window ID equals `"mySettings"` | the window is built | the window's accessibility identifier equals the slug of `"mySettings"` |
| single-window-controller-018 | toolbar-button-mask | a window spec registered for the window ID with the toolbar-buttons setting limited to close | the window is built | only the close button is visible; miniaturize and zoom are hidden |
| single-window-controller-019 | toolbar-button-mask-default | no window spec registered for the window ID | the window is built | all three standard buttons keep the platform's default visibility |
| single-window-controller-020 | build-sequence | a persisted frame for the window ID | the window is built | the frame is restored and applied before the delegate is set (so the restore does not itself trigger move/resize bookkeeping), and the configuration hook has already run by this point |
| single-window-controller-021 | build-sequence | any | the window is built | the window property is assigned right after the content is set — before the toolbar button mask, HUD chrome, the configuration hook, frame restore, and delegate assignment all run — and the configuration hook is invoked exactly once, after the toolbar/HUD chrome steps and before the frame restore |
| single-window-controller-022 | registry-registration | any window ID | the controller is constructed | the window registry's lookup for that window ID returns this instance, even before the window is ever built |
| single-window-controller-023 | registry-registration-empty-id | window ID is empty | the controller is constructed | no crash occurs; the registry has no entry for the empty ID |
| single-window-controller-024 | quiet-presentation | the forces-front flag is not set | the window is shown | the window is sunk behind the desktop and ordered back rather than being pulled to the front; it remains visible and keeps its restored frame |
| single-window-controller-025 | show-window-convenience | any | the parameterless show-window operation is called | it behaves identically to showing with no sender |
| single-window-controller-026 | visibility-persist-on-show | the window's spec has visibility persistence enabled | the window is shown | the window frame manager records the window visible |
| single-window-controller-027 | dismiss-method | a visible window | dismiss is called | the window closes |
| single-window-controller-028 | visibility-persist-on-dismiss | the window's spec has visibility persistence enabled | dismiss is called | the window frame manager records the window hidden |
| single-window-controller-029 | is-visible | no window built yet | the visibility flag is read | it returns false |
| single-window-controller-030 | content-fit | a built window | the fit-to-content operation is called with a new size | the window's frame changes to accommodate the content size, anchored per the current anchor |
| single-window-controller-031 | content-fit-bail | a prior fit already applied for a given size/anchor pair | the fit-to-content operation is called again with the same size | the frame is not re-applied |
| single-window-controller-032 | fit-anchor-stability | two consecutive fits with different sizes, the window unmoved between them | the second fit runs | the second fit anchors to the same edge the first fit chose, rather than recomputing the anchor from the window's current frame |
| single-window-controller-033 | reentrant-fit-guard | the fit-to-content operation is applying a computed frame | that frame change triggers a resize callback | the resize does not trigger a nested call back into the content-refit machinery |
| single-window-controller-034 | content-size-provider | the content-size provider set to a callback returning a fixed size | the refit operation is called | the fit-to-content operation is invoked with that size and the window's frame changes to match |
| single-window-controller-035 | content-refit-gate | no content-size provider set | the refit operation is called | no frame change occurs |
| single-window-controller-036 | move-refit-debounce | a provider set, then two moves in quick succession | the second move's callback fires | only one refit occurs, timed 200ms after the second move (the first move's pending wait is canceled and restarted, not stacked) |
| single-window-controller-037 | refit-drag-deferral | a scheduled refit fires while a mouse button is held | the refit runs | the refit reschedules itself instead of applying immediately |
| single-window-controller-038 | move-triggers-refit | the content-size provider set | a window-move callback fires | a refit is scheduled; with no provider set, the same move schedules no refit |
| single-window-controller-039 | frame-persist-on-move | the window's spec has frame persistence enabled | a window-move callback fires | the window frame manager is called with the new frame |
| single-window-controller-040 | frame-persist-on-resize | the window's spec has frame persistence enabled | a window-resize callback fires | the window frame manager is called with the new frame |
| single-window-controller-041 | resize-refit-guard | a resize caused by the controller's own fit-to-content call | a window-resize callback fires | the refit operation is not triggered |
| single-window-controller-042 | visibility-persist-on-close | the window's spec has visibility persistence enabled | the user clicks the window's close button | the window frame manager records the window hidden |
| single-window-controller-043 | visibility-restore | the window's spec has visibility persistence enabled and persisted visibility is true | the visibility-restore operation is called | the window is shown |
| single-window-controller-044 | hud-configuration | any | a HUD configuration value is constructed | it captures a floating flag (default true) and a transparency value (default 1.0) |
| single-window-controller-045 | hud-chrome-opt-in | the HUD-configuration operation never called | the window is inspected | chrome is ordinary opaque, non-floating |
| single-window-controller-046 | hud-transparency-floor | a caller-supplied transparency below 0.3 | the HUD-configuration operation or the set-transparency operation is called | the applied opacity is clamped to 0.3, not the raw value |
| single-window-controller-047 | set-floating | any | the set-floating operation is called with true | the window's level becomes floating |
| single-window-controller-048 | set-floating | any | the set-floating operation is called with false | the window's level becomes normal |
| single-window-controller-049 | set-transparency | any | the set-transparency operation is called | the window's opacity is set to the given value, clamped to 0.3-1.0, independent of the level set by the set-floating operation |
| single-window-controller-050 | singleton-protocol-conformance | a subclass adopting the single-instance protocol supplying the current-instance accessor and shared-instance factory | the protocol extension operations are called | ensure-current, present, and is-open all work without further overrides |
| single-window-controller-051 | singleton-ensure-current | no current instance exists | ensure-current is called twice | the shared-instance factory runs once; the second call reuses the first instance |
| single-window-controller-052 | singleton-present | no current instance exists | present is called | a shared instance is created and shown |
| single-window-controller-053 | singleton-is-open | no current instance exists | is-open is called | it returns false |

## Edge Cases

- **Empty window ID**: the window registry's registration operation silently
  skips registration when the window ID is empty; the controller still
  builds and shows a window, it simply cannot be looked up by ID afterward.
  This is a deliberate no-op guard in the registry, not an error path.
- **Duplicate window ID across two live controllers**: the window registry's
  own documentation states its "one live controller per ID" assumption;
  registering a second controller under an ID already in use replaces the
  prior registry entry, so a lookup by that ID returns only the most
  recently registered instance. The prior controller's window is unaffected
  by the replacement — the registry simply stops tracking it.
- **The fit-to-content operation called with a zero or negative dimension**:
  the fit-to-content operation guards against a non-positive width or
  height by returning immediately without applying any frame change; a
  degenerate size therefore never reaches the content-hugging frame
  calculation or the platform's own minimum-size clamping (a minimum size is
  only ever threaded into a fit that actually runs).
- **Concurrent access from multiple threads**: Not applicable — the whole
  class is confined to a single designated thread, so the compiler prevents
  concurrent access from another thread; there is no runtime race to defend
  against.
- **Error/failure states**: Not applicable — none of this class's APIs are
  throwing or failable; window construction itself cannot fail with the
  parameters used here, so there is no error path to define.
- **Offline/disconnected state**: Not applicable — this class has no network
  dependency.
- **Unbounded settle-wait while the mouse button is held**: the debounced
  refit (see **move-refit-debounce**, **refit-drag-deferral**) reschedules
  itself indefinitely as long as a mouse button is held, with no maximum
  retry count; a pathologically long drag defers the refit for the duration
  of the drag rather than firing early with a stale frame. This is a
  deliberate tradeoff (see Design Decisions), not an unhandled failure.
- **The configuration hook mutates the delegate or frame**: Because the hook
  runs before delegate assignment and frame restoration (see
  **build-sequence**), any delegate-firing change the configuration hook
  makes (e.g. resizing the window) is observed by the resize callback like
  any other resize, including its frame-persistence save path.

## Configuration

| Option | Type | Effect | Source |
|---|---|---|---|
| Window ID | Text | Construction-time identity used for registry lookup and frame/visibility persistence keying | constructing the controller |
| Content | Content controller | Construction-time, fixed content of the window | constructing the controller |
| Title (override) | Text | Window's title bar text | computed property |
| Default content rect (override) | Rectangle | Fallback frame when nothing is persisted | computed property |
| Style options (override) | Style-option set | Chrome and, via the utility/HUD options, whether a utility-style window is built | computed property |
| Minimum size (override) | Size | Window's minimum content size | computed property |
| Configuration hook (override) | Callback | One-time additional setup after full assembly | overridable method |
| Content-size provider | Optional callback | Enables content-hugging refit after moves | settable property |
| Forces-front flag (class override) | Boolean | Whether showing the window additionally forces it fully to front regardless of quiet presentation | class-level property |
| HUD-configuration operation | (Boolean, Number) | Opts the window into translucent/floating HUD chrome | method call |

## Deep Linking

Not applicable — this class has no URL-scheme or deep-link handling of its
own; a subclass that wants deep-link-driven presentation would call the
present or show-window operation from its own link handler, which is outside
this class's responsibility.

## Localization

- The title property is an overridable plain-text property, not a bound,
  localization-aware text value. The base class supplies only the
  empty-string default; whichever plain text a subclass returns from its
  override is assigned directly to the window's title and is therefore
  unlocalized unless the subclass itself localizes it. This is the
  subclass's responsibility, not this class's — the base class introduces no
  localizable or unlocalized string literal of its own.

## Accessibility Options

- **Reduce Motion**: Not applicable — the class has no animation code path;
  window moves/resizes it performs (the fit-to-content operation, frame
  restoration) are instantaneous frame assignments, not animated
  transitions.
- **Increase Contrast**: Not applicable — the base class sets no colors of
  its own beyond HUD transparency, which is a deliberate translucency effect
  rather than a contrast-relevant foreground/background pairing.
- **Reduce Transparency**: Not applicable to the base (non-HUD)
  configuration, since no window built without the HUD-configuration
  operation has any translucency to reduce. For a HUD-configured window, the
  set-transparency operation sets translucency unconditionally from the
  caller-supplied value; the class does not observe the system's
  reduce-transparency accessibility setting, so a HUD window's opacity is
  never re-clamped toward opaque when the system setting is enabled.

## Feature Flags

Not applicable — the class reads no feature-flag system; all behavior is
governed by subclass overrides and directly-called configuration methods.

## Analytics

Not applicable — this class emits no analytics events of its own. Window
interaction tracking for recents is delegated entirely to the window
manager's interaction hook, which itself calls only the platform's own
recent-document API for document windows (a system API, not an analytics
call) and is a documented no-op for non-document windows.

## Privacy

The frame (position and size) and visibility of each window are persisted to
disk by the window frame manager, keyed by the window ID, whenever the
corresponding frame/visibility persistence flags are enabled (the default
behavior set enables both). This class itself does not choose the storage
location or retention policy — it is the trigger point (via the move,
resize, will-close, show, and dismiss callbacks) that calls into the window
frame manager's persistence, which retains the last-known frame and
visibility indefinitely until a caller outside this class clears it. No
content, document data, or personally identifying information is captured
by this class; only window geometry and shown/hidden state are stored.

## Logging

Not applicable — this class contains no logging calls of its own.

## Platform Notes

- **SwiftUI (`WindowGroup`/`Window` scenes)**: SwiftUI's native window scenes
  handle lazy creation and frame restoration declaratively; a SwiftUI
  equivalent would express the window ID as a scene identifier and rely on
  `@SceneStorage`/`defaultPosition`/`defaultSize` modifiers rather than an
  imperative window-controller subclass.
- **Jetpack Compose (Desktop)**: `Window`/`DialogWindow` composables with
  `rememberWindowState` provide the closest analog to persisted frame state;
  content-hugging resize would be expressed by observing content size in a
  `SubcomposeLayout` and calling `WindowState.size = ...`.
- **React / Web**: Not applicable in the same sense — a browser tab/window is
  not directly resizable or positionable by page script in the general case;
  an Electron/Tauri shell would map this recipe onto `BrowserWindow`
  geometry-persistence APIs instead.
- **AppKit (source platform)**: This recipe is extracted directly from the
  AppKit implementation, where the base class is `SingleWindowController`, an
  `open`, `@MainActor`-isolated `NSWindowController` / `NSWindowDelegate`
  subclass. "A utility-style window" is `NSPanel`, selected when
  `windowStyleMask` contains `.utilityWindow` or `.hudWindow`; otherwise
  `loadWindow()` builds a plain `NSWindow`. "Archive-based construction" is
  Cocoa's `NSCoder`-based `init?(coder:)`, marked
  `@available(*, unavailable)` here (a compile-time error), fatal if ever
  reached at runtime despite that. The window registry is
  `WindowManager.shared.registry`; the window frame manager is
  `WindowFrameManager`, reached through the `windowSpec` computed property
  `WindowFrameManager.swift` adds to this class in an extension. The
  accessibility identifier is produced by `AccessibilityID.slug(_:)`; the
  toolbar-buttons setting is `WindowSpec.toolbarButtons`, an option set
  masking `NSWindow.standardWindowButton` visibility. "Forcing the window
  fully to front" is `window?.orderFrontRegardless()`; quiet presentation
  calls `window.sinkBehindDesktop()` then `window.orderBack(nil)`, with no
  `NSApp.activate(ignoringOtherApps:)` call — `SingletonWindowController
  .present()` separately calls `NSApplication.activateUnlessQuiet()` to
  avoid stealing app-wide focus. The window's opacity is `alphaValue`; the
  floating level is `NSWindow.Level.floating` vs `.normal`. The
  single-instance protocol is `SingletonWindowController`, providing
  `ensureCurrent()`, `present()`, and `isOpen()` from a protocol extension
  over a conforming type's `static var current` and `static func
  makeShared()`. The reduce-transparency accessibility setting is
  `NSWorkspace.accessibilityDisplayShouldReduceTransparency`, which this
  class does not observe. The recent-document API is
  `NSDocumentController.shared.noteNewRecentDocumentURL`, called from
  `WindowManager.windowDidInteract(_:kind:)`. The content-refit machinery's
  private implementation names — `isApplyingContentFit` (reentrancy guard),
  `wantsRefitAfterMove` (computed gate), `moveRefitSettleTask` /
  `scheduleContentRefitAfterMove()` (the debounce timer, checking
  `NSEvent.pressedMouseButtons`), and the reused `FrameAnchors` (anchor-hold
  state) — are internal to this class; only their observable effects are
  asserted above.
- **WinUI 3 / Windows App SDK**: This recipe exists specifically to give the
  Windows port a single-instance-window equivalent base. A `Microsoft
  .UI.Xaml.Window` subclass would map `defaultSize`/`minSize` to
  `AppWindow.Resize`/`AppWindow.MinSize` (or `OverlappedPresenter`
  constraints), frame persistence to `ApplicationData.LocalSettings` keyed by
  the window ID, HUD-style translucency to a `SystemBackdrop`
  (`MicaBackdrop`/`DesktopAcrylicBackdrop`) rather than raw alpha, and the
  toolbar-button mask to `AppWindowTitleBar` button-visibility properties.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/Windows/SingleWindowController.swift` |

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

## Compliance

| Check | Status | Category |
|---|---|---|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |

Statuses rest on direct inspection of `SingleWindowController.swift`: native
`NSWindow`/`NSPanel` construction with no custom-drawn chrome
(native-controls-preference), an explicit accessibility identifier derived
from `windowID` (screen-reader-support), and no-op repeats of
`fitWindow`/`showWindow`/`ensureCurrent` when nothing has changed
(idempotent-operations).

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from the Apple `SingleWindowController` (AppKit, macOS) source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reframed the requirement-count design decision as deliberate coupling debt rather than scope justification; merged the loadWindow build-order requirements into one build-sequence requirement and corrected registry-registration timing to init(); renamed init-argument-storage to describe storage only; renamed all requirements to subject-only kebab-case; reworded windowSpec citations as "a registered WindowSpec"; corrected the forces-front/quiet-presentation, HUD transparency/floating/transparency-property wording; moved private refit-machinery names out of requirements and test vectors into Platform Notes; replaced test vectors 001 and 037 with behavioral vectors, added a setFloating(false) vector, and merged the forces-front vectors; corrected the fitWindow zero/negative-size edge case against the real guard clause; moved the platform-design-languages reference into related and added sibling recipe links; removed the macos tag; reformatted Compliance to Check/Status/Category and Design Decisions to bold labels; ran compliance_fix.py to drop uncataloged Compliance checks; rejected the default-placement, double-persist, and compliance-coverage findings against current source. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/windows/. |
