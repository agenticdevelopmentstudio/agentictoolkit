<!-- leaf: implement-general-2/spacing-control--part-3 · source: spacing-control.md -->

# SpacingControl — continued (part 3)

## Platform Notes

- **SwiftUI**: Model `Spacing` as an `@Binding` (or an `ObservableObject`)
  and draw the diagram with a `Canvas`/layered `Rectangle` shapes inside a
  fixed `.frame(width: 420, height: 250)`, applying the same `minimumSize`
  floor via `.frame(minWidth:minHeight:)` to mirror
  clips-below-minimum-size. Represent each arrow as a borderless `Button`
  with an SF Symbol `Image` (`"arrow.up"`, etc.) tinted `.accentColor`;
  SwiftUI's `Button` has no built-in continuous/periodic action, so
  mirroring repeats-held-arrow needs a `DispatchSourceTimer` (or a
  `Timer`) started on `.onLongPressGesture(minimumDuration: 0,
  pressing:)`'s press phase, at the same `0.45`s delay / `0.06`s interval.
  Bind each number to a `TextField` with a numeric `Formatter`, committing
  on `.onSubmit` to mirror commits-field-on-editing-end, and drive each
  handle with a `DragGesture(minimumDistance: 0)` measuring `.translation`
  from the gesture's start, applying the same 1:1 (edge) / 2:1 (gutter)
  gains.
- **Compose**: Draw the diagram with `Canvas`, sized
  `Modifier.size(420.dp, 250.dp)` with a `Modifier.sizeIn(minWidth =,
  minHeight =)` floor mirroring clips-below-minimum-size. Use `IconButton`s
  with `Icons.Filled.ArrowUpward`/etc. tinted via `MaterialTheme
  .colorScheme.primary` (the accent-tint analog), driving repeats-held-arrow
  with `Modifier.pointerInput` detecting `awaitFirstDown()` followed by a
  coroutine `while (isPressed) { delay(...); adjust(); }` loop at the same
  `450`ms/`60`ms cadence. Use `BasicTextField` with numeric
  `KeyboardOptions`, committing on `ImeAction.Done` or focus loss to
  mirror commits-field-on-editing-end, and `Modifier.draggable` (per
  handle, `Orientation.Horizontal`/`Vertical`) recording the value at drag
  start and accumulating each `onDelta` into a running total displacement —
  never applying a delta straight to the value — then computing
  `value = startValue + gain × totalDisplacement` on every callback, to
  mirror "measured from the value at drag start, not accumulated step by
  step".
- **React/Web**: Render the diagram as absolutely-positioned elements (or
  inline SVG) inside a fixed `420×250px` container with a `min-width`/
  `min-height` floor mirroring clips-below-minimum-size. Represent each
  arrow as a `<button>` with an SVG chevron tinted via `currentColor`/an
  accent CSS variable, driving repeats-held-arrow with `setInterval`
  (`450`ms initial delay, then a `60`ms interval, cleared on
  `pointerup`/`pointerleave`). Use an `<input>` that commits on `blur`/
  `Enter` (mirroring commits-field-on-editing-end) rather than on every
  `input` event, and a `pointerdown`-installed/`pointerup`-removed
  `pointermove` listener per handle that records the pointer's client
  position and the value at `pointerdown`, then on each `pointermove`
  computes the total displacement from that start position — not
  accumulated `movementX`/`movementY` deltas — and applies the same
  1:1/2:1 gains to it, to mirror "measured from the value at drag start,
  not accumulated step by step".
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/UI/Controls/Spacing/SpacingControl.swift`,
  with two companions this recipe also draws from:
  `Spacing.swift` (the `Spacing` value type and the `SpacingEdge`/
  `SpacingGutter`/`SpacingArrow`/`SpacingAxis` enums it edits) and
  `SpacingControlLayout.swift` (the pure, view-independent geometry — chrome
  metrics, pane/gutter rects, arrow/field anchor points). macOS-only
  (`import AppKit`); there is no UIKit code path in source, and no
  touch-input handling to port. A UIKit/iOS port would need to redesign the
  hold-to-repeat arrows and the drag handles for touch
  (`UILongPressGestureRecognizer`/`UIPanGestureRecognizer`), since
  AppKit's `NSEvent`-loop-based tracking (`SpacingHandle.track(from:)`,
  `claimsPress`) has no UIKit equivalent.
- **WinUI 3**: Build the diagram as a
  `Canvas` (or a `Grid` of `Border` elements for the container/panes)
  inside a `UserControl` with `Width="420" Height="250"` and a `MinWidth`/
  `MinHeight` floor mirroring clips-below-minimum-size. Draw the outer
  frame and panes as `Border`/`Rectangle` elements whose `Background`/
  `BorderBrush` are bound to `ThemeResource` brushes mirroring
  `SemanticPalette`'s `.border`/`.windowBackground`/project-pane tokens —
  never a literal `Color`, matching this file's theme-token-only-colors
  discipline. Represent each arrow as a chrome-less `Button`
  (`Background="Transparent" BorderThickness="0"`) hosting a `FontIcon`/
  `PathIcon` glyph tinted with an accent `ThemeResource`; WinUI's
  `RepeatButton` (with its own `Delay`/`Interval` properties) is a closer
  built-in match for repeats-held-arrow than a plain `Button` plus a
  hand-rolled `DispatcherTimer`, and should replace it outright, configured
  to the same `450`ms delay / `60`ms interval. Bind each number to a
  `NumberBox` (`SpinButtonPlacementMode="Compact"` supplies the stepper for
  free) with `Minimum`/`Maximum` bound to `range`, committing via
  `ValueChanged` only after `LostFocus`/Enter to mirror
  commits-field-on-editing-end. `NumberBox`'s built-in
  `ValidationMode="InvalidInputOverwritten"` only reverts to the previous
  value on any unparseable text, which is not the full analog of
  recovers-unparseable-field-text: that requirement still wants the
  *clamped* typed number when one can be parsed — even from an out-of-range
  or partially-numeric string — and falls back to the held number only when
  nothing parses at all. Closing that gap needs a custom `TextSubmitted`
  handler that parses the typed text itself, clamps a successful parse to
  `range`, and reverts to the held number only when parsing fails outright.
  Implement the drag handles with `ManipulationMode="TranslateX,TranslateY"`
  and a `ManipulationDelta` handler computing the same 1:1 (edge) / 2:1
  (gutter) gains, and route `KeyDown` (`VirtualKey.Up`/`Down`) plus
  explicit `TabIndex` ordering (top/leading/trailing/bottom, or gutter
  order) across the `NumberBox`es to mirror tab-order-is-picture-order and
  arrow-keys-adjust-focused-field, since WinUI's default tab-index
  navigation cannot infer the picture's reading order from `Canvas`-based
  placement any more than AppKit's inferred key-view loop could from
  frame-based placement.

## Design Decisions

- **Decision**: Keep the range's floor and ceiling out of the fields'
  `NumberFormatter` and clamp only inside `Spacing.setting(_:in:)`/
  `Spacing.adjusting(_:by:in:)`.
  **Rationale**: the source comment on `makeField` explains that a
  `NumberFormatter` with a `maximum` refuses out-of-range text outright
  rather than clamping it, and AppKit answers that refusal by declining to
  end editing — trapping the caret in an emptied field. `Spacing` is the
  one place that can clamp instead of reject.
  **Approved**: pending
- **Decision**: Give arrow buttons and steppers `refusesFirstResponder = true`,
  keeping Tab limited to the four or two number fields, depending on
  `style`.
  **Rationale**: the source comments on `makeStepper`/`makeArrowButton` state
  that a stepper or an arrow in the tab loop would put extra stops between
  two number fields — Tab is for the numbers.
  **Approved**: pending
- **Decision**: Intercept Tab explicitly inside `control(_:textView:doCommandBy:)`
  rather than relying on AppKit's inferred key-view loop, and only within
  the control — at either end, focus is handed back to whatever
  `nextKeyView` the panel wired up.
  **Rationale**: the source comment explains that this control's subviews are
  frame-placed, not constraint-placed, so AppKit's inferred loop would
  thread the control's numbers in among whatever else the panel shows; a
  closed ring was considered and rejected as a focus trap.
  **Approved**: pending
- **Decision**: Bound `SpacingHandle.claimsPress`'s wait at `patience` (`0.3`s)
  in addition to the per-event `grace` (`0.12`s).
  **Rationale**: the source comment explains a resting trackpad delivers a
  steady trickle of sub-`slop` jitter events that each restart an unbounded
  `grace` timer, making a held-still arrow's repeat unreachable on a
  trackpad (though reachable on a mouse, which is genuinely silent);
  bounding the total wait fixes the trackpad case without shortening the
  mouse case.
  **Approved**: pending
- **Decision**: Scale the diagram 1:1 with the value, capped at
  `maximumDisplayedInset` (`40pt`), rather than compressing the whole range
  into a smaller diagram.
  **Rationale**: the source comment on `maximumDisplayedInset` explains that an
  arrow standing against the edge it moves travels with that edge; at a
  smaller display scale, a pressed arrow could slide most of its own length
  out from under a held pointer and stop repeating before the range ended.
  The 1:1 cap, paired with freezing a pressed pair's seat
  (freezes-pressed-arrow-pair), is what keeps a full-range hold under the
  pointer.
  **Approved**: pending
