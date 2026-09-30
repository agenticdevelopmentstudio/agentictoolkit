<!-- leaf: implement-window/controller · source: window-controller.md -->

**Rules** (cite as `implement-window/controller#<slug>`):

- `inherits-single-window-controller-lifecycle` MUST
- `exposes-typed-view-controller-accessor` MUST
- `returns-nil-for-non-matching-content-view-controller` MUST
- `declares-no-additional-initializer` MUST
- `exposes-typed-content-view-property` MUST
- `initializes-view-controller-with-supplied-content-view` MUST
- `provides-parameterless-convenience-initializer` MUST
- `fails-at-runtime-on-coder-initialization` MUST
- `installs-content-view-directly-in-load-view` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `contentView` (`WindowContentViewController`) | `ViewType` | none via `init(contentView:)`; `ViewType()` when constructed via the parameterless `convenience init()` | The strongly-typed view installed as `self.view` in `loadView()`. |
| `viewController` (`WindowController`) | `ViewControllerType?` | n/a — read-only computed accessor | Typed view of the window's `contentViewController`; `nil` when the actual `contentViewController` is not a `ViewControllerType`. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — the component performs no animation or motion of any kind. |
| Increase Contrast | Not applicable — the component sets no color values. |
| Differentiate Without Color | Not applicable — no state in the component is conveyed by color. |

## Privacy

- **Data collected**: None.
- **Storage**: None — the component persists nothing of its own; whatever
  frame/visibility persistence occurs on a `WindowController` instance is
  `SingleWindowController`'s behavior, already documented in
  `agentictoolkit://recipes/single-window-controller`.
- **Transmission**: Not applicable — the component contains no network code.
- **Retention**: Not applicable — the component retains no data.

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
