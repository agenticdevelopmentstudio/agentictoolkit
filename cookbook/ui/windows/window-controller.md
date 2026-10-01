---
id: 8ed694b4-e238-48c5-9589-81ce6aaebb32
title: Typed Window Content
domain: agentictoolkit://cookbook/ui/windows/window-controller
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A generic window controller adding a typed content accessor over the
  single-instance window base, paired with a generic wrapper that installs a
  strongly-typed view as a content controller.
platforms:
- swift
- macos
tags:
- window-controller
- view-controller
depends-on:
- agentictoolkit://cookbook/ui/windows/single-window-controller
related: []
references: []
approved-by: ''
approved-date: ''
---

# Typed Window Content

## Overview

Two small generic types, defined together, give call sites typed access to a
window's content instead of the untyped content controller that the
single-instance window base's content accessor returns.

The window controller is an open subclass of the single-instance window base
(see `agentictoolkit://cookbook/ui/windows/single-window-controller`, which
this recipe depends on and does not restate) that adds exactly one member: a
computed typed accessor that downcasts the base's content to a
caller-supplied content-controller type. It overrides nothing else and
declares no initializer of its own, so every other behavior — lazy window
construction, frame/visibility persistence, HUD chrome, front-ordering under
quiet presentation, the singleton protocol extension — is exactly what the
base class specifies.

The content wrapper is a separate, unrelated-by-inheritance content
controller that wraps a single strongly-typed view as a content controller's
content, for call sites that need a content controller (e.g. to hand to the
window controller's content accessor) but only have a view. It stores the
view at construction and overrides the view-loading step to install it
directly, bypassing nib/resource loading entirely.

## Behavioral Requirements

- **inherits-single-window-controller-lifecycle**: The window controller
  MUST inherit all window build, frame-persistence, visibility-persistence,
  and HUD behavior unchanged from the single-instance window base (see
  `agentictoolkit://cookbook/ui/windows/single-window-controller`), since it
  overrides no member of the base.
- **exposes-typed-view-controller-accessor**: The window controller MUST
  expose a computed typed accessor equal to the base's content, downcast to
  the caller-supplied content-controller type.
- **returns-nil-for-non-matching-content-view-controller**: The typed
  accessor MUST evaluate to absent whenever the base's content is absent or
  is not an instance of the caller-supplied content-controller type.
- **declares-no-additional-initializer**: The window controller MUST declare
  no initializer of its own, so construction and archive-based-construction
  behavior remain exactly the base class's.
- **exposes-typed-content-view-property**: The content wrapper MUST expose a
  content-view property, of the caller-supplied view type, set once, at
  construction.
- **initializes-view-controller-with-supplied-content-view**: Constructing
  the content wrapper with a supplied view MUST assign the given view to the
  content-view property and complete the base content-controller
  construction with no resource/nib reference.
- **provides-parameterless-convenience-initializer**: The content wrapper
  MUST expose a parameterless convenience construction path that constructs
  a default instance of the caller-supplied view type and forwards it to the
  view-supplying construction path.
- **fails-at-runtime-on-archive-initialization**: Archive-based construction
  of the content wrapper MUST trap with a fatal error at runtime, so
  decoding-based initialization is unsupported.
- **installs-content-view-directly-in-load-view**: The view-loading step
  MUST be overridden to install the content-view property as the
  controller's view directly, with no nib/resource loading or additional
  view hierarchy construction.

## Appearance

- **Corner radius**: Not applicable — neither type draws or configures any
  view of its own; the content view's appearance is entirely the caller's.
- **Padding**: Not applicable — same reason.
- **Font**: Not applicable — same reason.
- **Background**: Not applicable — neither type sets a background of its
  own; the window's own background is the single-instance window base's
  concern (already documented there).
- **Foreground/Text**: Not applicable — the component renders no text of its
  own.
- **Border**: Not applicable — the component draws no border of its own.
- **Shadow**: Not applicable — the component applies no shadow of its own.
- **Min/Max size**: Not applicable — window sizing is the single-instance
  window base's concern; neither type adds a size constraint of its own.

## States

| State | Behavior |
|-------|------------------|
| Default (matching content type) | The typed accessor returns the base's content downcast to the caller-supplied content-controller type |
| Mismatched or absent content controller | The typed accessor returns absent |
| Content wrapper constructed, view not yet loaded | The content-view property already exists (set at construction); the controller's view has not been created yet — the platform's normal lazy view-loading timing applies |
| Content wrapper's view loaded | The controller's view is the content-view property instance |
| Pressed | Not applicable — neither type is an interactive control; the component renders nothing and has no press-state code. |
| Disabled | Not applicable — neither type has an enabled/disabled state of its own. |
| Focused | Not applicable — neither class overrides key-view or first-responder handling. |
| Loading | Not applicable — the typed accessor's cast and the view-loading step's assignment are both synchronous; there is no asynchronous loading state. |

## Accessibility

- Role/trait: Not applicable — the component sets no accessibility role,
  trait, or identifier of its own. The window's accessibility identifier is
  already the single-instance window base's concern (see
  `agentictoolkit://cookbook/ui/windows/single-window-controller`); any
  content-level role belongs to whatever content-controller or view type the
  caller supplies — a child component with its own recipe, not this one.
- Label requirements: Not applicable — the component sets no label, for the
  same reason.
- Announce state changes: Not applicable — the component makes no
  accessibility-announcement call of its own.
- Minimum tap target: Not applicable — the component defines no interactive
  control of its own; the content view's target sizing is the
  caller-supplied view's concern.

## Conformance Test Vectors

| ID | Requirements | Input | Action | Expected |
|----|-------------|-------|--------|----------|
| window-controller-001 | inherits-single-window-controller-lifecycle | a window-controller subclass instance | the show-window operation is called | the window builds, shows, and persists frame/visibility exactly as the single-instance window base specifies |
| window-controller-002 | exposes-typed-view-controller-accessor | a window controller whose content is an instance of the target content-controller type | the typed accessor is read | the same instance is returned, typed as the target content-controller type |
| window-controller-003 | returns-nil-for-non-matching-content-view-controller | a window controller whose content is absent or a different content-controller type | the typed accessor is read | absent is returned |
| window-controller-004 | declares-no-additional-initializer | any window-controller subclass | attempt the base class's window-ID/content construction path, and separately attempt archive-based construction | the base construction path compiles and constructs the instance; the archive-based construction path does not compile, since the window controller declares no initializer of its own and inherits the base class's construction-by-archive being made unavailable there |
| window-controller-005 | exposes-typed-content-view-property | a content wrapper built with the view-supplying construction path | the content-view property is read | it returns the exact instance passed at construction |
| window-controller-006 | initializes-view-controller-with-supplied-content-view | a view instance `v` | the content wrapper is constructed with `v` | the content-view property is `v` and the instance is a fully initialized content controller |
| window-controller-007 | provides-parameterless-convenience-initializer | a view type with a working parameterless construction path | the content wrapper's parameterless construction path is used | the content-view property is a freshly constructed default instance of that view type |
| window-controller-008 | fails-at-runtime-on-archive-initialization | a content-wrapper type | archive-based construction is invoked from a death-test run in a separate process (an in-process test cannot assert a process trap; treat as review-only where a death-test harness is unavailable) | the process traps with a fatal error |
| window-controller-009 | installs-content-view-directly-in-load-view | a constructed content wrapper | the view-loading step runs (triggered by first access to the controller's view) | the controller's view is the content-view property instance, with no nib/resource loaded |

## Edge Cases

- **Null/empty input**: the base's content property reassigned to absent
  after construction (it is a settable, inherited property) — the typed
  accessor returns absent rather than crashing, per
  **returns-nil-for-non-matching-content-view-controller**. MUST.
- **Boundary values**: Not applicable — the caller-supplied content-controller
  type and view type are reference-type generic constraints, not measured or
  bounded inputs.
- **Concurrent access**: The window controller is confined to a single
  designated thread by inheritance from the single-instance window base's own
  thread confinement. The content wrapper declares no explicit thread
  confinement of its own, but the platform's content-controller base is
  itself confined to that same thread in the platform overlay, so the wrapper
  inherits that confinement the same way. Neither type adds an additional
  concurrency guard of its own.
- **Error states**: Not applicable beyond the deliberate fatal error in
  archive-based construction — no throwing or failable operation exists in
  the component.
- **Offline/disconnected state**: Not applicable — the component has no
  network dependency.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Content view (content wrapper) | Caller-supplied view type | none via the view-supplying construction path; a freshly constructed default instance when built via the parameterless convenience construction path | The strongly-typed view installed as the controller's view during the view-loading step. |
| Typed accessor (window controller) | Caller-supplied content-controller type (optional) | n/a — read-only computed accessor | Typed view of the window's content; absent when the actual content is not an instance of the caller-supplied content-controller type. |

## Deep Linking

Not applicable: the component defines no URL-scheme or deep-link handling of
its own.

## Localization

Not applicable: the component introduces no string literal at all — no bound
text value or title assignment of any kind anywhere in its source.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — the component performs no animation or motion of any kind. |
| Increase Contrast | Not applicable — the component sets no color values. |
| Differentiate Without Color | Not applicable — no state in the component is conveyed by color. |

## Feature Flags

Not applicable: the component reads no feature-flag system of its own.

## Analytics

Not applicable: the component emits no analytics events of its own.
Window-interaction tracking is the single-instance window base's concern
(already documented as delegated to the window manager's interaction hook in
`agentictoolkit://cookbook/ui/windows/single-window-controller`).

## Privacy

- **Data collected**: None.
- **Storage**: None — the component persists nothing of its own; whatever
  frame/visibility persistence occurs on a window-controller instance is the
  single-instance window base's behavior, already documented in
  `agentictoolkit://cookbook/ui/windows/single-window-controller`.
- **Transmission**: Not applicable — the component contains no network code.
- **Retention**: Not applicable — the component retains no data.

## Logging

Not applicable: the component contains no logging calls of its own.

## Platform Notes

- **SwiftUI**: This generics-over-a-view-controller pattern has no direct
  SwiftUI analog because SwiftUI content *is* the typed value already — a
  `WindowGroup`/`Window` scene's root `View` is accessed and composed
  directly, with no untyped `contentViewController`-style intermediary to
  downcast. A SwiftUI port would drop the window controller's typed accessor
  entirely and drop the content wrapper's wrapping role along with it.
- **Compose (Desktop)**: Same reasoning as SwiftUI — a `Window`/`DialogWindow`
  composable takes its content as a `@Composable` lambda with full static
  typing already, so there is no untyped content slot to wrap or downcast.
- **React/Web**: A browser window has no view-controller layer at all;
  the closest analog to a typed accessor is a typed `ref` on a child
  component (e.g. `useRef<ContentHandle>()`), used only when a parent needs
  imperative access to a specific child's instance methods.
- **AppKit / UIKit**: `WindowController.swift` defines both types for AppKit.
  `WindowController<ViewControllerType>` is specific to this file for its
  `as?`-based typed accessor over `NSWindowController.contentViewController`
  and for adding no initializer of its own; it is `@MainActor`-isolated by
  inheritance from `SingleWindowController`'s explicit `@MainActor` (Swift's
  global-actor inheritance rule). `WindowContentViewController<ViewType>`
  is specific to this file for overriding `loadView()` to skip nib loading
  and for the coder initializer's runtime-only failure (`init?(coder:)`
  calling `fatalError("init(coder:) has not been implemented")`, see Design
  Decisions); it declares no explicit `@MainActor` of its own, but
  `NSViewController` itself is `@MainActor`-isolated in the AppKit overlay,
  so the subclass inherits that isolation the same way. UIKit has no
  `NSWindowController` equivalent, so `WindowController`'s typed accessor has
  no direct UIKit counterpart; but `WindowContentViewController`'s pattern
  maps directly, since `UIViewController` also declares `loadView()` for
  installing a view without a nib, exactly as this class overrides it here.
- **WinUI 3**: There is no `NSViewController`-equivalent generic content
  controller sitting inside a WinUI `Window` — content is set directly via
  `Window.Content` (a `UIElement`), and navigation/lifecycle parity is
  usually obtained through a `Frame.Navigate(typeof(PageType))` call instead.
  The typed-accessor half of this recipe maps to a small `TypedWindow<TPage>`
  wrapper holding a `Window` and a `Frame`, exposing
  `CurrentPage: TPage? => Frame.Content as TPage` in place of
  `viewController`. The content-wrapping half maps to setting
  `Window.Content = rootElement` directly for a plain `UIElement`, or, when
  page-navigation parity with `NSViewController`'s lifecycle is wanted,
  wrapping `rootElement` inside a `Page` subclass and setting it as
  `Frame.Content`. No dedicated WinUI visual states apply, since both
  `WindowController` and `WindowContentViewController` are plumbing classes,
  not rendered controls.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/Windows/WindowController.swift` |

## Design Decisions

**Decision**: Document only what `WindowController.swift` itself adds — the
typed `viewController` accessor and `WindowContentViewController` — and treat
all window lifecycle, frame-persistence, visibility-persistence, and HUD
behavior as inherited unchanged from `SingleWindowController`, cited through
`depends-on` rather than restated.
**Rationale**: `SingleWindowController` already has its own canonical recipe
(`agentictoolkit://cookbook/ui/windows/single-window-controller`); restating its
requirements here would duplicate content that has its own source of truth
and risks drift when that recipe changes, and would misrepresent this file's
actual (much smaller) scope.
**Approved**: pending

**Decision**: Document `WindowContentViewController.init?(coder:)`'s
runtime-only `fatalError` as a quirk rather than describing it as matching
`SingleWindowController`'s coder-rejection pattern.
**Rationale**: source fidelity forbids smoothing over an inconsistency —
`SingleWindowController.init?(coder:)` is marked `@available(*, unavailable)`
(a compile-time failure), while `WindowContentViewController.init?(coder:)`
carries no such attribute and remains a normally callable initializer that
only fails at runtime when actually invoked.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |

Statuses rest on both types being built entirely from stock
`NSWindowController`/`NSViewController` plumbing with no custom-drawn chrome;
and on the file adding no accessibility identifier or label of its own while
not obstructing whatever the caller-supplied `ViewControllerType`/`ViewType`
provides.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from the Apple `WindowController.swift` source (`WindowController<ViewControllerType>` and `WindowContentViewController<ViewType>`). |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reformat Design Decisions to bold three-line form; fix the Compliance table's Category column and drop inapplicable checks (no-raw-hex, differentiate-without-color, localizable-strings, idempotent-operations); rename the AppKit Platform Notes bullet to AppKit / UIKit and add the UIKit equivalent; remove Accessibility Options template residue; state `NSViewController`'s inherited `@MainActor` isolation outright instead of hedging; add a Conformance Test Vectors Action column and rework vectors 004 and 008 into a compile-time check and a death-test check; rename the States column to Behavior; and rewrite file-coupled "Not applicable" justifications to describe the component's behavior. |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Compliance: removed rows for checks absent from the cookbook catalog |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/windows/. |
