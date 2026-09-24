---
id: 8ed694b4-e238-48c5-9589-81ce6aaebb32
title: WindowController
domain: agentictoolkit://recipes/window-controller
type: ingredient
version: 1.0.0
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
- **Background**: Not applicable — `WindowController.swift` sets no
  background; the window's own background is `SingleWindowController`'s
  concern (already documented there).
- **Foreground/Text**: Not applicable — no text is rendered by this file.
- **Border**: Not applicable — no border is drawn by this file.
- **Shadow**: Not applicable — no shadow is applied by this file.
- **Min/Max size**: Not applicable — window sizing is `SingleWindowController`'s
  concern; this file adds no size constraint of its own.

## States

| State | Appearance change |
|-------|------------------|
| Default (matching content type) | `viewController` returns `contentViewController` downcast to `ViewControllerType` |
| Mismatched or absent content view controller | `viewController` returns `nil` |
| `WindowContentViewController` constructed, view not yet loaded | `contentView` already exists (set at `init`); `view` has not been created yet — AppKit's normal lazy `NSViewController.loadView()` timing applies |
| `WindowContentViewController` view loaded | `self.view === contentView` |
| Pressed | Not applicable — neither class is an interactive control; `WindowController.swift` renders nothing and has no press-state code. |
| Disabled | Not applicable — neither class has an enabled/disabled state of its own in this file. |
| Focused | Not applicable — neither class overrides key-view or first-responder handling. |
| Loading | Not applicable — `viewController`'s cast and `loadView()`'s view assignment are both synchronous; there is no asynchronous loading state. |

## Accessibility

- Role/trait: Not applicable — `WindowController.swift` sets no
  `NSAccessibility` role, trait, or identifier of its own. The window's
  accessibility identifier is already `SingleWindowController`'s concern (see
  `agentictoolkit://recipes/single-window-controller`); any content-level role
  belongs to whatever `ViewControllerType`/`ViewType` the caller supplies —
  a child component with its own recipe, not this one.
- Label requirements: Not applicable — no label is set by this file for the
  same reason.
- Announce state changes: Not applicable — this file makes no
  `NSAccessibility.post(element:notification:)` call.
- Minimum tap target: Not applicable — this file defines no interactive
  control of its own; `contentView`'s target sizing is the caller-supplied
  view's concern.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| window-controller-001 | inherits-single-window-controller-lifecycle | a `WindowController<SomeVC>` subclass instance | `showWindow()` is called | the window builds, shows, and persists frame/visibility exactly as `SingleWindowController` specifies |
| window-controller-002 | exposes-typed-view-controller-accessor | a `WindowController<SomeVC>` whose `contentViewController` is a `SomeVC` instance | `viewController` is read | the same instance is returned, typed as `SomeVC` |
| window-controller-003 | returns-nil-for-non-matching-content-view-controller | a `WindowController<SomeVC>` whose `contentViewController` is `nil` or a different `NSViewController` subclass | `viewController` is read | `nil` is returned |
| window-controller-004 | declares-no-additional-initializer | any `WindowController<T>` subclass | source is inspected | no initializer is declared in `WindowController`; only the inherited `init(windowID:contentViewController:)` and unavailable `init?(coder:)` are callable |
| window-controller-005 | exposes-typed-content-view-property | a `WindowContentViewController<NSView>` built with `init(contentView:)` | `contentView` is read | it returns the exact instance passed to `init` |
| window-controller-006 | initializes-view-controller-with-supplied-content-view | a view instance `v` | `WindowContentViewController(contentView: v)` is constructed | `contentView === v` and the instance is a fully initialized `NSViewController` |
| window-controller-007 | provides-parameterless-convenience-initializer | a `ViewType` with a working parameterless initializer | `WindowContentViewController<ViewType>()` is constructed | `contentView` is a freshly constructed `ViewType()` instance |
| window-controller-008 | fails-at-runtime-on-coder-initialization | any | `init?(coder:)` is invoked | the process traps with `fatalError("init(coder:) has not been implemented")` |
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
  of its own in this file; its isolation is whatever AppKit's `NSViewController`
  overlay provides. This file adds no additional concurrency guard of its
  own in either case.
- **Error states**: Not applicable beyond the deliberate `fatalError` in
  `init?(coder:)` — no throwing or failable API exists in this file.
- **Offline/disconnected state**: Not applicable — this file has no network
  dependency.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `contentView` (`WindowContentViewController`) | `ViewType` | none via `init(contentView:)`; `ViewType()` when constructed via the parameterless `convenience init()` | The strongly-typed view installed as `self.view` in `loadView()`. |
| `viewController` (`WindowController`) | `ViewControllerType?` | n/a — read-only computed accessor | Typed view of the window's `contentViewController`; `nil` when the actual `contentViewController` is not a `ViewControllerType`. |

## Deep Linking

Not applicable: `WindowController.swift` defines no URL-scheme or deep-link
handling of its own.

## Localization

Not applicable: `WindowController.swift` introduces no string literal at
all — no `Text`, `Label`, `stringValue`, or `title` assignment anywhere in
the file.

## Accessibility Options

Document which accessibility display options (Rule 15) this component
responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — the file performs no animation or motion of any kind. |
| Increase Contrast | Not applicable — the file sets no color values. |
| Differentiate Without Color | Not applicable — no state in this file is conveyed by color. |

## Feature Flags

Not applicable: `WindowController.swift` reads no feature-flag system of its
own.

## Analytics

Not applicable: `WindowController.swift` emits no analytics events of its
own. Window-interaction tracking is `SingleWindowController`'s concern
(already documented as delegated to `WindowManager.windowDidInteract(_:kind:)`
in `agentictoolkit://recipes/single-window-controller`).

## Privacy

- **Data collected**: None.
- **Storage**: None — this file persists nothing of its own; whatever
  frame/visibility persistence occurs on a `WindowController` instance is
  `SingleWindowController`'s behavior, already documented in
  `agentictoolkit://recipes/single-window-controller`.
- **Transmission**: Not applicable — no network code in this file.
- **Retention**: Not applicable — no data is retained by this file.

## Logging

Not applicable: `WindowController.swift` contains no logging calls of its
own.

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
- **AppKit (source platform)**: `WindowController.swift` defines both types.
  `WindowController<ViewControllerType>` is specific to this file for its
  `as?`-based typed accessor over `NSWindowController.contentViewController`
  and for adding no initializer of its own. `WindowContentViewController<ViewType>`
  is specific to this file for overriding `loadView()` to skip nib loading
  and for the coder initializer's runtime-only failure (see Design
  Decisions).
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

Decision: Document only what `WindowController.swift` itself adds — the
typed `viewController` accessor and `WindowContentViewController` — and treat
all window lifecycle, frame-persistence, visibility-persistence, and HUD
behavior as inherited unchanged from `SingleWindowController`, cited through
`depends-on` rather than restated.
Rationale: `SingleWindowController` already has its own canonical recipe
(`agentictoolkit://recipes/single-window-controller`); restating its
requirements here would duplicate content that has its own source of truth
and risks drift when that recipe changes, and would misrepresent this file's
actual (much smaller) scope.
Approved: pending

Decision: Document `WindowContentViewController.init?(coder:)`'s
runtime-only `fatalError` as a quirk rather than describing it as matching
`SingleWindowController`'s coder-rejection pattern.
Rationale: source fidelity forbids smoothing over an inconsistency —
`SingleWindowController.init?(coder:)` is marked `@available(*, unavailable)`
(a compile-time failure), while `WindowContentViewController.init?(coder:)`
carries no such attribute and remains a normally callable initializer that
only fails at runtime when actually invoked.
Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | `WindowController` is `@MainActor`-isolated by inheritance from `SingleWindowController`; `WindowContentViewController` carries no explicit annotation in this file and relies on AppKit's own `NSViewController` isolation. |
| [no-raw-hex](agenticdevelopercookbook://compliance/ui-tokens#no-raw-hex) | passed | Neither class sets any color value; there is no appearance code in this file at all. |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Built entirely from `NSWindowController`/`NSViewController` plumbing, with no custom-drawn chrome. |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | No state in this file is conveyed by color; it conveys no state of its own beyond the typed/`nil` accessor result. |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | This file adds no accessibility identifier or label of its own and does not obstruct whatever the caller-supplied `ViewControllerType`/`ViewType` provides. |
| [localizable-strings](agenticdevelopercookbook://compliance/i18n#localizable-strings) | passed | The file contains no string literal of any kind. |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | `viewController` is a pure computed read with no side effect; repeated reads return the same result for an unchanged `contentViewController`. |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from the Apple `WindowController.swift` source (`WindowController<ViewControllerType>` and `WindowContentViewController<ViewType>`). |
