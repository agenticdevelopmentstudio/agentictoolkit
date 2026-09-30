<!-- leaf: implement-general-view-1/chat-transcript-row-view--part-3 · source: chat-transcript-row-view.md -->

# Chat Transcript Row View — continued (part 3)

## Platform Notes

- **SwiftUI**: Compose a custom `View` mirroring this file's structure: a header (the session breadcrumb + icon, built the same way `SessionHeaderView` is used here), the bubble view, and a `Text` timestamp, stacked in a `VStack` whose `HorizontalAlignment` (`.leading`/`.trailing`) is chosen by `message.role`, exactly as `isFromUser` chooses anchors here. Use `.contentShape(Rectangle())` plus `.onTapGesture(count: 2)` for open and a plain `.onTapGesture` for select on the row's own background (SwiftUI, unlike AppKit's `NSEvent.clickCount`-based `mouseUp`, needs the two gesture recognizers arbitrated explicitly, e.g. with `.simultaneousGesture` or `.exclusively(before:)`), and `.onHover`/`.overlay` for the hover fill and selection border this file draws on its `CALayer`. Compute the bubble's max width from `GeometryReader` the way `maxBubbleWidth(forRowWidth:)` does here.
- **Compose**: Build a `Row`/`Column` composition — a header row (an app icon `Image`, clickable via its own `Modifier.clickable`, plus a breadcrumb `Text`), the bubble composable, and a timestamp `Text` — inside a parent `Box` using `Modifier.combinedClickable(onClick = onSelect, onDoubleClick = onOpen)`, which is Compose's direct equivalent of this file's single-click-select / double-click-open split. Use `Arrangement.End`/`Arrangement.Start` (mirroring `aligns-by-role`) and a `mutableStateOf` for a Compose-desktop hover fill; on Android there is no mouse hover to mirror, so that half of the behavior simply does not arise.
- **React/Web**: Render a flex column (header row, bubble, timestamp) inside a container `div` with `onClick` (select) and `onDoubleClick` (open) handlers — the DOM natively distinguishes single vs. double click the way this file's `NSEvent.clickCount` check does, so no extra arbitration is needed. Use CSS `:hover` for the fill, gated by a class or `data-` attribute mirroring `isPressable` so an unwired row (no `onOpen`) never shows it, and a `.selected` class applying `box-shadow`/`border` instead of `outline` to keep the "shape, not fill" cue this file uses. Compute the bubble's max width from a `ResizeObserver` on the row, mirroring `maxBubbleWidth(forRowWidth:)`.
- **AppKit / UIKit** (source platform): `ChatTranscriptRowView.swift`, an `NSView` subclass — this is a macOS/AppKit-only file with no UIKit counterpart in source. The header line reuses `SessionHeaderView`, the same control the Sessions window and Conversations shelf use, so its accessibility and layout are learned once across all three. Hover and selection are drawn as raw `CALayer` property writes (`backgroundColor`, `borderWidth`/`borderColor`) rather than `NSVisualEffectView` or a highlight subview. `hitTest(_:)` is overridden so the row remains the primary click target everywhere except over the bubble or the (wired) app-icon button, and `mouseUp`'s `event.clickCount` check is what separates single-click-select from double-click-open — a UIKit port has no `clickCount` on `UIView` touch events, so it would need a `UITapGestureRecognizer(numberOfTapsRequired: 2)` for open and a separate single-tap recognizer with `require(toFail:)` against it for select.
- **WinUI 3**: Start from a `UserControl` (or a `DataTemplate` inside a virtualizing `ItemsRepeater`/`ListView`, if the transcript is virtualized) containing a `Grid`: a header `StackPanel` (an `Image` or `PersonPicture` for the app icon, plus a breadcrumb `TextBlock`), the bubble content, and a `TextBlock` for the timestamp. Bind `HorizontalAlignment` between `Right` and `Left` to `message.role`, mirroring `aligns-by-role`. Drive hover and selection through `VisualStateManager` states (`PointerOver`, `Selected`) on the control's `ControlTemplate` rather than manually toggling layer properties — WinUI's built-in template states already express exactly the hover/selected distinction this file hand-codes. WinUI's `Tapped` and `DoubleTapped` events do not carry an AppKit-style `clickCount`; `Tapped` fires before a would-be `DoubleTapped` is recognized, so reconciling single-click-select against double-click-open requires either acting on `Tapped` only after `DoubleTapped`'s recognition window has elapsed, or accepting that select fires once before open also fires — which is in fact what this file itself does: `mouseDown` invokes `onSelect` unconditionally on every press, including the first press of a double click, and only `mouseUp`'s `clickCount >= 2` check decides open, so a double click here also fires select before it fires open (see **select-on-mouse-down**, **open-on-double-click**). The app icon becomes a `Button` (or `HyperlinkButton`) with `AutomationProperties.Name` bound to "Go to {headerLine}", mirroring the AppKit accessibility label, and `ToolTipService.ToolTip` for the hover tooltip. The 2px selection border becomes `BorderThickness="2"` on the template's `Border`, driven by the `Selected` visual state, rather than a manually toggled `CALayer` border.

## Design Decisions

**Decision**: The app icon is sized 28×28pt — short of the 44pt the Sessions window gives the identical control, but larger than the 24pt symbol it replaces.
**Rationale**: In the transcript, the icon heads one line of a timeline whose subject is what was said, not the row's whole identity the way it is in the Sessions window; 28pt keeps it recognizable as artwork (a picture to be recognised, not a glyph to be read) without claiming the row.
**Approved: pending**

**Decision**: The app icon's target, tooltip, and accessibility label are set only when `actions.onJump` is non-nil; an unwired icon renders with no target.
**Rationale**: The icon promises a link under the pointer wherever it is hovered; a promise kept by nothing is worse than no promise, so the promise is only made where it is actually kept.
**Approved: pending**

**Decision**: Hover fill and the pointing-hand cursor are gated on `actions.onOpen`, not on `actions.onSelect` or `actions.onJump`.
**Rationale**: They promise that pressing the row itself means something — specifically, that a press opens the conversation — so they track the row's own primary action rather than any closure being present.
**Approved: pending**

**Decision**: Selection is drawn as a 2pt border rather than a background fill.
**Rationale**: The hover fill already means "the mouse is here"; a second fill would leave a reader unable to tell a hovered row from a selected one, and a border leaves the bubble's own color — which encodes who is talking — untouched.
**Approved: pending**

**Decision**: Opening a row requires a double click; a single click is reserved for selection and for starting a text-selection drag inside the bubble.
**Rationale**: A single click is worth more where it already is — selecting text to copy it — and opening a conversation is deliberate enough to be worth two clicks instead of contesting that gesture.
**Approved: pending**

**Decision**: The row is laid out with hand-written `NSLayoutConstraint`s mirrored per role, rather than nested stack views, with the header line as the one exception (it stays a stack).
**Rationale**: The row mirrors about its own centre line, and "the same layout, flipped" is one set of anchors chosen per side, where stack views would need two separate hierarchies; the header line is the shared control used identically in the Sessions window and Conversations shelf, so it keeps its own internal arrangement regardless of which margin the whole line is pinned to.
**Approved: pending**

**Decision**: `showsInlineTimestamp: false` is passed to the embedded bubble, and the row draws its own timestamp label on its own line instead.
**Rationale**: The row's own timestamp is anchored to the same edge as the header's breadcrumb trail — the speaker's column — so it has to be a label this row positions itself; a timestamp the bubble drew inline would be part of the bubble's own shape and could not be pinned independently to that column (see `agentictoolkit://recipes/ai-chat-bubble-view`).
**Approved: pending**
