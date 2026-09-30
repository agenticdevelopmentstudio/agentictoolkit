<!-- leaf: implement-general-view-1/button-view · source: button-view.md -->

**Rules** (cite as `implement-general-view-1/button-view#<slug>`):

- `creates-button-with-viewmodel-title` MUST
- `reads-title-once-at-init` MUST
- `retains-view-model-strongly` MUST
- `exposes-button-publicly` MUST
- `disables-autoresizing-mask-translation` MUST
- `adds-button-as-subview` MUST
- `defaults-placement-to-fill` MUST
- `placement-fixed-at-init` MUST
- `fills-view-in-fill-placement` MUST
- `constrains-vertical-edges-in-non-fill-placement` MUST
- `caps-trailing-edge-in-non-fill-placement` MUST
- `aligns-leading-edge-in-leading-placement` MUST
- `floors-leading-edge-in-centered-placement` MUST
- `centers-button-in-centered-placement` MUST
- `wires-button-action` MUST
- `invokes-pressed-callback` MUST
- `takes-no-action-without-callback` MUST
- `rejects-frame-initializer` MUST
- `rejects-coder-initializer` MUST
- `confines-to-main-actor` MUST

# Button View

## Overview

`ButtonView` is an AppKit `NSView` from the ComposableSettingsWindow system integration (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ButtonView.swift`) that wraps a single `NSButton` as one settings row and conforms to `SettingsViewProtocol`. Its title and the action performed on press are both driven entirely by a caller-supplied `ButtonViewModel`, not configured on the view itself. A nested `Placement` enum controls how the button sits in the row it is given: stretched across the whole row (`.fill`, the default), sized to its own title at the row's leading edge (`.leading`), or sized to its own title and centered in the row (`.centered`).

`ButtonViewModel` (`ComposableSettingsWindow/ViewModels/ButtonViewModel.swift`) is a `class` subclassing `AbstractViewModel`. It exposes `title: String` (immutable — declared `let` on `AbstractViewModel`) and `wasPressedCallback: (() -> Void)?` (mutable, `internal`, default `nil`); `AbstractViewModel` also carries `explanation: String?` (immutable), which `ButtonView` never reads.

## Behavioral Requirements

- **creates-button-with-viewmodel-title**: The component MUST initialize its `button` property as an `NSButton` whose title is `viewModel.title`, with no target or action set at creation time.
- **reads-title-once-at-init**: The component MUST read `viewModel.title` only once, at initialization, to construct `button`'s title; it never re-reads `viewModel.title` afterward. `ButtonViewModel.title` (inherited from `AbstractViewModel`) is declared `let`, so there is no later point at which a changed value could exist to re-read.
- **retains-view-model-strongly**: The component MUST hold `viewModel` as a strong reference (`private let viewModel: ButtonViewModel`) for its own lifetime, keeping `viewModel` — and any closure it holds, including `wasPressedCallback` — alive at least as long as the view itself.
- **exposes-button-publicly**: The component MUST expose the underlying `NSButton` as a public, read-only `button` property.
- **disables-autoresizing-mask-translation**: The component MUST set `translatesAutoresizingMaskIntoConstraints = false` on both itself and `button`.
- **adds-button-as-subview**: The component MUST add `button` as a subview of itself.
- **defaults-placement-to-fill**: The component MUST default its `placement` initializer parameter to `.fill` when the caller supplies none.
- **placement-fixed-at-init**: The component MUST fix `placement`'s effect on `button`'s constraints at initialization; it exposes no property or method to change `placement`, or to re-run the placement logic, after construction.
- **fills-view-in-fill-placement**: WHEN `placement` is `.fill`, the component MUST pin all four edges of `button` to the corresponding edges of the view, so `button` occupies the view's full bounds.
- **constrains-vertical-edges-in-non-fill-placement**: WHEN `placement` is `.leading` or `.centered`, the component MUST constrain `button`'s top and bottom edges to equal the view's top and bottom edges.
- **caps-trailing-edge-in-non-fill-placement**: WHEN `placement` is `.leading` or `.centered`, the component MUST constrain `button`'s trailing edge to be less than or equal to the view's trailing edge, so `button` never extends past the view.
- **aligns-leading-edge-in-leading-placement**: WHEN `placement` is `.leading`, the component MUST constrain `button`'s leading edge to equal the view's leading edge.
- **floors-leading-edge-in-centered-placement**: WHEN `placement` is `.centered`, the component MUST constrain `button`'s leading edge to be greater than or equal to the view's leading edge.
- **centers-button-in-centered-placement**: WHEN `placement` is `.centered`, the component MUST constrain `button`'s horizontal center to equal the view's horizontal center.
- **wires-button-action**: The component MUST set `button.target` to itself and `button.action` to its `buttonWasPressed(_:)` selector.
- **invokes-pressed-callback**: WHEN `button` is pressed AND `viewModel.wasPressedCallback` is non-nil, the component MUST invoke `viewModel.wasPressedCallback`.
- **takes-no-action-without-callback**: WHEN `button` is pressed AND `viewModel.wasPressedCallback` is nil, the component MUST NOT perform any action beyond `button`'s own native press feedback.
- **rejects-frame-initializer**: The component MUST fatal-error if constructed through the inherited `NSView.init(frame:)` initializer.
- **rejects-coder-initializer**: The component MUST fatal-error if constructed through `init?(coder:)`.
- **confines-to-main-actor**: The component MUST be usable only on the main actor; the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not set by `ButtonView`; governed entirely by `NSButton`'s default bezel style — no `bezelStyle`, `isBordered`, or layer customization appears in source.
- **Padding**: Not set; `ButtonView` applies no internal padding around `button`. Any inset between the button's content and its own edge is `NSButton`'s unmodified default.
- **Font**: Not set; `button.font` is never assigned, so `NSButton(title:target:action:)`'s default control font applies.
- **Background**: Not set; `ButtonView` performs no drawing or layer coloring of its own.
- **Foreground/Text**: Not set; no `attributedTitle` or `contentTintColor` customization appears in source, so `NSButton`'s default title color applies.
- **Border**: Not set; no border or bezel customization appears in source.
- **Shadow**: Not set; no shadow customization appears in source.
- **Min/Max size**: Not set via explicit width/height constraints. In `.fill`, `button`'s size equals the view's bounds (via `pinToEdges`). In `.leading`/`.centered`, `button`'s height equals the view's height (top and bottom pinned); its width is bounded by the trailing cap (and, for `.centered`, the leading floor) but not fixed — the final width is `button`'s own intrinsic content size for its title, constrained not to exceed the view.

## Accessibility

- **Role**: `button`, inherited from `NSButton`; `ButtonView` sets no custom accessibility role.
- **Label**: The accessible name is `button`'s title, set from `viewModel.title` at construction (see **creates-button-with-viewmodel-title**); `ButtonView` sets no separate accessibility label.
- **Announce state changes**: Not applicable: `ButtonView` defines no disabled or loading state of its own (see States); if a caller disables `button` directly, the enabled/disabled announcement is `NSButton`'s native behavior, not something `ButtonView` implements.
- **Keyboard navigation**: Inherited from `NSButton` — Tab/Shift-Tab move focus onto and off the button, and Space or Return activates it through the target/action wired in **wires-button-action**. `ButtonView` adds no custom key handling.
- **Minimum tap target**: `ButtonView` keeps AppKit's system metrics for `button` — no `controlSize`, width or height override — so the click target is the regular-size push-button bezel sized to its title, as the macOS Human Interface Guidelines prescribe for pointer-driven controls. A port to touch platforms would need to give the equivalent control at least the platform minimum (44×44 pt on iOS, 48×48 dp on Android, 40×40 epx on WinUI 3); this is porting guidance, not a behavior of the AppKit source.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ButtonViewModel` | (required) | A `class` (subclass of `AbstractViewModel`) supplying `button`'s title (`title: String`, immutable) and the optional `wasPressedCallback: (() -> Void)?` closure invoked when `button` is pressed (mutable, default `nil`). |
| `placement` | `ButtonView.Placement` | `.fill` | Where `button` sits in its row: `.fill` stretches it across the whole row, `.leading` sizes it to its title at the row's leading edge, `.centered` sizes it to its title and centers it in the row. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none) | (none) | `viewModel.title` is supplied entirely by the caller; `ButtonView` defines no string keys or default text of its own. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `ButtonView` applies no animation or transition of its own; any press animation is `NSButton`'s unconditional system-level bezel feedback, which this component neither adds nor could gate. |
| Increase Contrast | Not applicable: `ButtonView` sets no custom colors of its own; all coloring is `NSButton`'s default system appearance, which already tracks the system's Increase Contrast setting. |
| Differentiate Without Color | Not applicable: `ButtonView` conveys no state through color; it defines exactly one visual presentation (the button with its title), and any color-based state such as pressed or disabled is `NSButton`'s own system chrome. |

## Privacy

- **Data collected**: None. `ButtonView` holds only the `title` string and a closure reference passed in by the caller through `ButtonViewModel`; it collects nothing of its own.
- **Storage**: N/A — no persistence; state lives only in memory for the view's lifetime.
- **Transmission**: N/A — `ButtonView` performs no network or IPC calls.
- **Retention**: N/A — nothing is retained beyond the view's lifetime.

