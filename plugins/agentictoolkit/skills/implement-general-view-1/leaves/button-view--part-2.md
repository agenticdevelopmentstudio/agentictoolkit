<!-- leaf: implement-general-view-1/button-view--part-2 · source: button-view.md -->

# Button View — continued (part 2)

## Platform Notes

- **SwiftUI**: Replace with `Button(viewModel.title) { viewModel.wasPressedCallback?() }`. Map `.fill` to `.frame(maxWidth: .infinity)` on the button (with a full-width button style so the tap target itself stretches, not just its label); map `.leading` to placing the button first in an `HStack` followed by a `Spacer()`, or `.frame(maxWidth: .infinity, alignment: .leading)`; map `.centered` to `.frame(maxWidth: .infinity, alignment: .center)`. No `fatalError`-guarded initializer is needed — SwiftUI views have no counterpart to `init(frame:)`/`init?(coder:)`.
- **Compose**: Replace with `Button(onClick = { viewModel.wasPressedCallback?.invoke() }) { Text(viewModel.title) }`. Map `.fill` to `Modifier.fillMaxWidth()` on the `Button`; map `.leading` to `Modifier.fillMaxWidth().wrapContentWidth(Alignment.Start)` on the `Button` inside a `Row`, so the button occupies the row's width but sizes and aligns its own tap target to its label at the start (mirroring the trailing-capped, leading-pinned constraints); map `.centered` to `Modifier.align(Alignment.CenterHorizontally)` in a `Column`, or `Arrangement.Center` in a `Row`.
- **React/Web**: Replace with `<button onClick={() => viewModel.wasPressedCallback?.()}>{viewModel.title}</button>`. Map `.fill` to `width: 100%` (or `display: block`) on the button; map `.leading` to `justify-content: flex-start` on a flex row containing the button; map `.centered` to `justify-content: center` on that row, or `margin-inline: auto` on the button itself.
- **AppKit / UIKit (source)**: `ButtonView.swift` is macOS-only (`import AppKit`) — there is no iOS/UIKit counterpart in this file. It is an `NSView` wrapping one `NSButton`, computing its three Auto Layout placements once at `init` time (placement cannot change after construction), with `init(frame:)` and `init?(coder:)` fatal-erroring rather than being usable, and the whole type isolated to `@MainActor`. A UIKit port to `UIView`/`UIButton` would need to add the enabled/highlighted/selected state handling that `NSButton`'s bezel already provides on macOS but `UIButton` requires more explicit configuration for.
- **WinUI 3**: Use a `Button` control with `Content` bound to `viewModel.Title` and `Click` wired to the equivalent of `buttonWasPressed`. Map `.fill` to `HorizontalAlignment="Stretch"` with `HorizontalContentAlignment="Stretch"`, placed in the row's `Grid` cell so it spans the row's width (mirroring `pinToEdges`); map `.leading` to `HorizontalAlignment="Left"` in that same cell (mirroring the top/bottom-pinned, trailing-capped constraints); map `.centered` to `HorizontalAlignment="Center"` (mirroring the leading-floored, center-x-pinned constraints). WinUI has no `fatalError`-style initializer guard, so enforce "always construct with a view model" through a required constructor parameter or a `required` property instead of a runtime crash on an unused inherited initializer. `Button`'s built-in `CommonStates` (`Normal`, `PointerOver`, `Pressed`, `Disabled`) via `VisualStateManager` already cover pressed/disabled visuals without custom state XAML, matching the source's own lack of custom pressed/disabled styling.

## Design Decisions

**Decision**: `.fill` is the default value of the `placement` parameter.
**Rationale**: Per the source's own doc comment, the default is `.fill` "because that is what every caller before this parameter got, and a settings row that silently changed shape would be a worse surprise than a verbose call site."
**Approved**: pending

**Decision**: The `.leading` and `.centered` placements bound `button`'s trailing edge (and, for `.centered`, its leading edge) with inequality constraints rather than pinning them exactly.
**Rationale**: Per the source's own comments: the trailing constraint is "less-than, not equal: the row is as wide as the card, and an equal trailing edge is the stretch `.fill` is for," and the `.centered` leading constraint is "greater-than... for the same reason as the trailing one; the centre anchor does the placing."
**Approved**: pending

**Decision**: `init(frame:)` and `init?(coder:)` are overridden only to call `fatalError`, rather than being omitted.
**Rationale**: `ButtonView` has no valid state without a `ButtonViewModel`. Blocking the two inherited `NSView` initializers this way means a caller who reaches them through generic `NSView`-typed construction code (e.g. Interface Builder decoding) crashes immediately with a diagnosable message, instead of silently producing a `ButtonView` with no view model.
**Approved**: pending

**Decision**: This recipe calls `ButtonView`'s container a "row" throughout, even though the source's own comments use both "row" (in the `Placement` doc comment: "where the button sits in the row it is given") and "card" (in the `.fill` and `.leading` case comments: "stretched across the whole card"; "the row is as wide as the card").
**Rationale**: The two words refer to the same concept in this file; "row" is kept as the single term for consistency with how a `SettingsViewProtocol` view's container is described elsewhere in the cookbook — `agentictoolkit://recipes/header-view` and `agentictoolkit://recipes/horizontal-stack-view` both describe `SettingsViewProtocol` as "the marker protocol every settings-row view in this system adopts" — and the source's own inconsistency is recorded here rather than silently smoothed over.
**Approved**: pending

**Decision**: This recipe describes `Self.pinToEdges(button, of: self)` (used in **fills-view-in-fill-placement**) as pinning all four edges of `button` to the corresponding edges of `self`.
**Rationale**: `pinToEdges` is not defined in `ButtonView.swift`, but its implementation was read directly: `static func pinToEdges(_ view: NSView, of container: NSView)` in `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/ViewLayout.swift` activates exactly four equal constraints — `view`'s top, leading, trailing, and bottom anchors to `container`'s corresponding anchors — confirming the `.fill` case comment ("Stretched across the whole card") describes the same behavior this recipe asserts.
**Approved**: pending
