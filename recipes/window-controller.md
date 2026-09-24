---
id: 8ed694b4-e238-48c5-9589-81ce6aaebb32
title: WindowController
domain: agentictoolkit://recipes/window-controller
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Generic AppKit window controller adding a typed content-view-controller accessor
  over SingleWindowController, paired with a generic typed content-view wrapper.
platforms:
- swift
- macos
tags:
- window-controller
- view-controller
- macos
- appkit
depends-on:
- agentictoolkit://recipes/single-window-controller
related: []
references: []
approved-by: ''
approved-date: ''
---

# WindowController

## Overview

`WindowController<ViewControllerType>` and `WindowContentViewController<ViewType>`
are two small generic types, defined together in `WindowController.swift`, that
give AppKit call sites typed access to a window's content instead of the
untyped `NSViewController` that `NSWindowController.contentViewController`
returns.

`WindowController<ViewControllerType: NSViewController>` is an `open` subclass
of `SingleWindowController` that adds exactly one member: a computed
`viewController: ViewControllerType?` that downcasts `contentViewController`.
It overrides nothing else and declares no initializer of its own, so every
other behavior — lazy window construction, frame/visibility persistence, HUD
chrome, front-ordering under quiet presentation, the singleton protocol
extension — is exactly what `SingleWindowController` specifies (see
`agentictoolkit://recipes/single-window-controller`, which this recipe depends
on and does not restate).

`WindowContentViewController<ViewType: NSView>` is a separate, unrelated-by-
inheritance `open NSViewController` subclass that wraps a single strongly-typed
`NSView` as a view controller's content, for call sites that need an
`NSViewController` (e.g. to hand to `WindowController`'s
`contentViewController`) but only have a view. It stores the view at `init`
and overrides `loadView()` to install it directly, bypassing nib loading
entirely.

## Behavioral Requirements

- **inherits-single-window-controller-lifecycle**: `WindowController<ViewControllerType>`
  MUST inherit all window build, frame-persistence, visibility-persistence,
  and HUD behavior unchanged from `SingleWindowController` (see
  `agentictoolkit://recipes/single-window-controller`), since it overrides no
  `SingleWindowController` member.
- **exposes-typed-view-controller-accessor**: `WindowController<ViewControllerType>`
  MUST expose a computed `viewController: ViewControllerType?` property equal
  to `contentViewController as? ViewControllerType`.
- **returns-nil-for-non-matching-content-view-controller**: `viewController`
  MUST evaluate to `nil` whenever `contentViewController` is `nil` or is not
  an instance of `ViewControllerType`.
- **declares-no-additional-initializer**: `WindowController<ViewControllerType>`
  MUST declare no initializer of its own, so construction and
  `init?(coder:)` behavior remain exactly `SingleWindowController`'s.
- **exposes-typed-content-view-property**: `WindowContentViewController<ViewType>`
  MUST expose a `let contentView: ViewType` set once, at initialization.
- **initializes-view-controller-with-supplied-content-view**:
  `init(contentView:)` MUST assign the given view to `contentView` and call
  `super.init(nibName: nil, bundle: nil)`.
- **provides-parameterless-convenience-initializer**:
  `WindowContentViewController<ViewType>` MUST expose a `convenience init()`
  that constructs `ViewType()` and forwards it to `init(contentView:)`.
- **fails-at-runtime-on-coder-initialization**: `init?(coder:)` MUST call
  `fatalError("init(coder:) has not been implemented")`, so decoding-based
  initialization is unsupported.
- **installs-content-view-directly-in-load-view**: `loadView()` MUST be
  overridden to set `self.view = contentView` directly, with no nib loading
  or additional view hierarchy construction.

## Appearance

- **Corner radius**: Not applicable — neither class draws or configures any
  view of its own; `contentView`'s appearance is entirely the caller's.
- **Padding**: Not applicable — same reason.
- **Font**: Not applicable — same reason.
- **Background**: Not applicable — neither type sets a background of its own;
  the window's own background is `SingleWindowController`'s concern (already
  documented there).
- **Foreground/Text**: Not applicable — the component renders no text of its
  own.
- **Border**: Not applicable — the component draws no border of its own.
- **Shadow**: Not applicable — the component applies no shadow of its own.
- **Min/Max size**: Not applicable — window sizing is `SingleWindowController`'s
  concern; neither type adds a size constraint of its own.

## States

| State | Behavior |
|-------|------------------|
| Default (matching content type) | `viewController` returns `contentViewController` downcast to `ViewControllerType` |
| Mismatched or absent content view controller | `viewController` returns `nil` |
| `WindowContentViewController` constructed, view not yet loaded | `contentView` already exists (set at `init`); `view` has not been created yet — AppKit's normal lazy `NSViewController.loadView()` timing applies |
| `WindowContentViewController` view loaded | `self.view === contentView` |
| Pressed | Not applicable — neither type is an interactive control; the component renders nothing and has no press-state code. |
| Disabled | Not applicable — neither type has an enabled/disabled state of its own. |
| Focused | Not applicable — neither class overrides key-view or first-responder handling. |
| Loading | Not applicable — `viewController`'s cast and `loadView()`'s view assignment are both synchronous; there is no asynchronous loading state. |

## Accessibility

- Role/trait: Not applicable — the component sets no `NSAccessibility` role,
  trait, or identifier of its own. The window's accessibility identifier is
  already `SingleWindowController`'s concern (see
  `agentictoolkit://recipes/single-window-controller`); any content-level role
  belongs to whatever `ViewControllerType`/`ViewType` the caller supplies —
  a child component with its own recipe, not this one.
- Label requirements: Not applicable — the component sets no label, for the
  same reason.
- Announce state changes: Not applicable — the component makes no
  `NSAccessibility.post(element:notification:)` call.
- Minimum tap target: Not applicable — the component defines no interactive
  control of its own; `contentView`'s target sizing is the caller-supplied
  view's concern.

## Conformance Test Vectors

| ID | Requirements | Input | Action | Expected |
|----|-------------|-------|--------|----------|
| window-controller-001 | inherits-single-window-controller-lifecycle | a `WindowController<SomeVC>` subclass instance | `showWindow()` is called | the window builds, shows, and persists frame/visibility exactly as `SingleWindowController` specifies |
| window-controller-002 | exposes-typed-view-controller-accessor | a `WindowController<SomeVC>` whose `contentViewController` is a `SomeVC` instance | `viewController` is read | the same instance is returned, typed as `SomeVC` |
| window-controller-003 | returns-nil-for-non-matching-content-view-controller | a `WindowController<SomeVC>` whose `contentViewController` is `nil` or a different `NSViewController` subclass | `viewController` is read | `nil` is returned |
| window-controller-004 | declares-no-additional-initializer | any `WindowController<T>` subclass | attempt to call `init(windowID:contentViewController:)`, and separately attempt to call `init?(coder:)` | the `init(windowID:contentViewController:)` call compiles and constructs the instance; the `init?(coder:)` call does not compile, since `WindowController` declares no initializer of its own and inherits `SingleWindowController`'s `@available(*, unavailable)` `init?(coder:)` |
| window-controller-005 | exposes-typed-content-view-property | a `WindowContentViewController<NSView>` built with `init(contentView:)` | `contentView` is read | it returns the exact instance passed to `init` |
| window-controller-006 | initializes-view-controller-with-supplied-content-view | a view instance `v` | `WindowContentViewController(contentView: v)` is constructed | `contentView === v` and the instance is a fully initialized `NSViewController` |
| window-controller-007 | provides-parameterless-convenience-initializer | a `ViewType` with a working parameterless initializer | `WindowContentViewController<ViewType>()` is constructed | `contentView` is a freshly constructed `ViewType()` instance |
| window-controller-008 | fails-at-runtime-on-coder-initialization | a `WindowContentViewController<ViewType>` type | `init?(coder:)` is invoked from a death test run in a separate process (an in-process `XCTest` cannot assert a process trap; treat as review-only where a death-test harness is unavailable) | the process traps with `fatalError("init(coder:) has not been implemented")` |
| window-controller-009 | installs-content-view-directly-in-load-view | a constructed `WindowContentViewController` | `loadView()` runs (triggered by first access to `view`) | `self.view === contentView`, with no nib loaded |

## Edge Cases

- **Null/empty input**: `contentViewController` reassigned to `nil` after
  construction (it is a settable, inherited `NSViewController?` property) —
  `viewController` returns `nil` rather than crashing, per
  **returns-nil-for-non-matching-content-view-controller**. MUST.
- **Boundary values**: Not applicable — `ViewControllerType` and `ViewType`
  are reference-type generic constraints, not measured or bounded inputs.
- **Concurrent access**: `WindowController<ViewControllerType>` is
  `@MainActor`-isolated by inheritance from `SingleWindowController`'s
  explicit `@MainActor` (Swift's global-actor inheritance rule).
  `WindowContentViewController<ViewType>` declares no explicit `@MainActor`
  of its own, but `NSViewController` itself is `@MainActor`-isolated in the
  AppKit overlay, so the subclass inherits that isolation the same way.
  Neither type adds an additional concurrency guard of its own.
- **Error states**: Not applicable beyond the deliberate `fatalError` in
  `init?(coder:)` — no throwing or failable API exists in the component.
- **Offline/disconnected state**: Not applicable — the component has no
  network dependency.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `contentView` (`WindowContentViewController`) | `ViewType` | none via `init(contentView:)`; `ViewType()` when constructed via the parameterless `convenience init()` | The strongly-typed view installed as `self.view` in `loadView()`. |
| `viewController` (`WindowController`) | `ViewControllerType?` | n/a — read-only computed accessor | Typed view of the window's `contentViewController`; `nil` when the actual `contentViewController` is not a `ViewControllerType`. |

## Deep Linking

Not applicable: the component defines no URL-scheme or deep-link handling of
its own.

## Localization

Not applicable: the component introduces no string literal at all — no
`Text`, `Label`, `stringValue`, or `title` assignment anywhere in its source.

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
Window-interaction tracking is `SingleWindowController`'s concern
(already documented as delegated to `WindowManager.windowDidInteract(_:kind:)`
in `agentictoolkit://recipes/single-window-controller`).

## Privacy

- **Data collected**: None.
- **Storage**: None — the component persists nothing of its own; whatever
  frame/visibility persistence occurs on a `WindowController` instance is
  `SingleWindowController`'s behavior, already documented in
  `agentictoolkit://recipes/single-window-controller`.
- **Transmission**: Not applicable — the component contains no network code.
- **Retention**: Not applicable — the component retains no data.

## Logging

Not applicable: the component contains no logging calls of its own.

## Platform Notes

- **SwiftUI**: This generics-over-a-view-controller pattern has no direct
  SwiftUI analog because SwiftUI content *is* the typed value already — a
  `WindowGroup`/`Window` scene's root `View` is accessed and composed
  directly, with no untyped `contentViewController`-style intermediary to
  downcast. A SwiftUI port would drop `WindowController`'s typed accessor
  entirely and drop `WindowContentViewController`'s wrapping role along with
  it.
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
  and for adding no initializer of its own. `WindowContentViewController<ViewType>`
  is specific to this file for overriding `loadView()` to skip nib loading
  and for the coder initializer's runtime-only failure (see Design
  Decisions). UIKit has no `NSWindowController` equivalent, so
  `WindowController`'s typed accessor has no direct UIKit counterpart; but
  `WindowContentViewController`'s pattern maps directly, since
  `UIViewController` also declares `loadView()` for installing a view
  without a nib, exactly as this class overrides it here.
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

## Design Decisions

**Decision**: Document only what `WindowController.swift` itself adds — the
typed `viewController` accessor and `WindowContentViewController` — and treat
all window lifecycle, frame-persistence, visibility-persistence, and HUD
behavior as inherited unchanged from `SingleWindowController`, cited through
`depends-on` rather than restated.
**Rationale**: `SingleWindowController` already has its own canonical recipe
(`agentictoolkit://recipes/single-window-controller`); restating its
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
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | Architecture |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |

Statuses rest on `WindowController` inheriting `@MainActor` isolation from
`SingleWindowController` and `WindowContentViewController` inheriting it from
`NSViewController`, which the AppKit overlay marks `@MainActor` in the SDK;
on both types being built entirely from stock `NSWindowController`/
`NSViewController` plumbing with no custom-drawn chrome; and on the file
adding no accessibility identifier or label of its own while not obstructing
whatever the caller-supplied `ViewControllerType`/`ViewType` provides.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from the Apple `WindowController.swift` source (`WindowController<ViewControllerType>` and `WindowContentViewController<ViewType>`). |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reformat Design Decisions to bold three-line form; fix the Compliance table's Category column and drop inapplicable checks (no-raw-hex, differentiate-without-color, localizable-strings, idempotent-operations); rename the AppKit Platform Notes bullet to AppKit / UIKit and add the UIKit equivalent; remove Accessibility Options template residue; state `NSViewController`'s inherited `@MainActor` isolation outright instead of hedging; add a Conformance Test Vectors Action column and rework vectors 004 and 008 into a compile-time check and a death-test check; rename the States column to Behavior; and rewrite file-coupled "Not applicable" justifications to describe the component's behavior. |
