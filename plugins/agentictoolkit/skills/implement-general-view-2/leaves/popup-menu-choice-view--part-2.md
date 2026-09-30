<!-- leaf: implement-general-view-2/popup-menu-choice-view--part-2 · source: popup-menu-choice-view.md -->

# PopupMenuChoiceView — continued (part 2)

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call; every state change is an instantaneous property assignment (`label.stringValue`, `popUpButton.selectItem(at:)`). |
| Increase Contrast | Partial: `PopupMenuChoiceView.swift` sets no custom `NSColor` of its own on `popUpButton`, so any Increase Contrast response for the popup itself comes from AppKit's own default control rendering, not from code in this file. The label's color comes from the theme's `.primaryText` role (`SemanticPalette.derive`, resolving to a fixed `theme.foreground`); the source does not show that role itself adapting to Increase Contrast, so a stronger claim than "partial" is not supported here. |
| Differentiate Without Color | Not applicable: the current choice is communicated through the popup's own item title text (and an optional symbol image), not through a color-only signal introduced by this component. |

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays choices and a value supplied by `viewModel`
  and reports selection changes back through `viewModel.settingObserver`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by the
  `ComposableSettings.ChoiceViewModel<Value>`/`settingObserver`, which are
  not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews
  (`label`, `popUpButton`) and its reference to `viewModel` for its own
  lifetime; it persists nothing beyond that.

## Platform Notes

- **SwiftUI**: Replace with a `Picker(viewModel.title, selection: $value)`
  built from `ForEach(viewModel.choices, id: \.value)` rows, each branching
  on `choice.imageSystemName`: `Label(choice.label, systemImage:
  symbolName)` when it is non-`nil`, or plain `Text(choice.label)` when it
  is `nil` — never `systemImage: choice.imageSystemName ?? ""`, since an
  empty symbol name renders a broken image — with `.pickerStyle(.menu)` to
  match the borderless popup affordance; wrap it
  with a leading `Text(viewModel.title)` in an `HStack` (or a
  `LabeledContent`) if the row shape from `makeRow` should be kept
  literally rather than relying on `Picker`'s own built-in label. Commit
  the selection to the underlying setting from the `Binding`'s setter with
  an equality guard, mirroring skips-redundant-commits; a selection whose
  raw value doesn't decode to a known choice mirrors
  ignores-unresolvable-selection by leaving the setting unchanged.
- **Compose**: Use an `ExposedDropdownMenuBox` (or a plain `Row` opening a
  `DropdownMenu`) with a leading `Text(title)` and a trailing read-only
  field/anchor showing the current choice's label; each `DropdownMenuItem`
  renders `choice.label`, with an optional leading `Icon` when an icon
  resource is supplied (the Compose analog of `imageSystemName`). Commit
  the tapped item's value to the backing state/view-model in
  `onClick`/`onItemSelected` with an equality check before writing,
  mirroring skips-redundant-commits, and leave the state unchanged if the
  clicked item's value can't be resolved, mirroring
  ignores-unresolvable-selection.
- **React/Web**: A flex row (`display: flex; align-items: center;
  justify-content: space-between`) containing a `<label>` for the title and
  a `<select>` whose `<option>` elements are built from `choices` (value =
  the choice's serialized value, text = `choice.label`), with the
  `<select>`'s `aria-labelledby` (or an explicit `<label for>`) pointing at
  the title `<label>`'s `id` — the web analog of
  `setAccessibilityTitleUIElement`. Commit the new value on the `<select>`'s
  `onChange` handler, comparing against the previous value before calling
  the parent's setter to mirror skips-redundant-commits, and ignoring a
  value that doesn't map to a known option to mirror
  ignores-unresolvable-selection.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PopupMenuChoiceView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, generic
  over `Value: Codable & Sendable & Equatable`, inside the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It
  composes two subviews — an `NSTextField` label from
  `ComposableSettings.makeRowLabel` and a borderless `NSPopUpButton`
  populated from `ChoiceViewModel.choices` — into one row via
  `ComposableSettings.makeRow` and `pinToEdges`. Per added item,
  **attaches-choice-value-to-item** is implemented by setting
  `representedObject` to `choice.value`, and **attaches-choice-image** by
  setting `image` to `NSImage(systemSymbolName: choice.imageSystemName,
  accessibilityDescription: nil)` when non-`nil`.
  **suppresses-popup-bezel** is `popUpButton.isBordered = false`;
  **resists-popup-stretch** is
  `popUpButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)`.
  **links-popup-accessibility-title** is
  `popUpButton.setAccessibilityTitleUIElement(label)`.
  **wires-popup-action** sets `popUpButton.target` to `self` and
  `popUpButton.action` to `Selector("popupChanged:")`, whose handler reads
  `sender.selectedItem?.representedObject as? Value`, guarding on the cast
  to implement **ignores-unresolvable-selection**, and on an equality check
  against `settingObserver.value` to implement **skips-redundant-commits**
  before writing (**commits-selection-value**). There is no UIKit code path
  in source; a UIKit port would replace `NSPopUpButton` with a `UIButton`
  presenting a `UIMenu` (or a `UIPickerView`) and the `target`/`action`
  pattern with `.addTarget(_:action:for: .primaryActionTriggered)` or a
  `UIAction` handler per menu item. `UIView` inherits the same
  `init(coder:)`-vs-`init(frame:)` split that `NSView` does — a UIKit port
  would fatal-error both initializers the same way
  **requires-designated-initializer** and
  **rejects-frame-only-initialization** do on `NSView`.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `*,Auto`: a `TextBlock` for the title in column 0
  (the `*` column lets the title claim the row's leading space, the WinUI
  analog of `makeRow`'s flexible spacer sitting between the label and the
  control); a `ComboBox` in column 1, `HorizontalAlignment="Right"`, styled
  without its default border/background (`BorderThickness="0"`,
  `Background="Transparent"`) to match `isBordered = false`'s bezel-less
  popup. Bind `ItemsSource` to the `choices` collection with
  `DisplayMemberPath="Label"` and `SelectedValuePath="Value"` (the WinUI
  analog of a menu item's title and `representedObject`); when a choice
  carries an icon, replace the plain `DisplayMemberPath` binding with a
  `ComboBoxItem` `DataTemplate` containing a `StackPanel` of a `FontIcon`
  (bound to the choice's icon glyph) followed by a `TextBlock` for
  `Label`, the WinUI analog of `NSImage(systemSymbolName:)`. Set
  `AutomationProperties.LabeledBy` on the `ComboBox` to the `TextBlock` —
  the WinUI analog of `setAccessibilityTitleUIElement` linking a bare
  control's name to its visible label. Commit the selection from
  `SelectionChanged`, first checking `SelectedValue` resolves to a known
  choice value (mirroring ignores-unresolvable-selection) and only
  then writing through a property setter that skips the assignment (and so
  skips raising `INotifyPropertyChanged`) when the incoming value already
  equals the current value, mirroring skips-redundant-commits.

## Design Decisions

**Decision**: Draw the popup fully borderless (`isBordered = false`)
instead of AppKit's default bezeled `NSPopUpButton`.
**Rationale**: Per the source's own comment, "System Settings draws a
popup inside a card without a bezel: the current value in secondary text
with the chevron pair after it. The card is the surface, so a second one
around the control just boxes a box."
**Approved**: pending

**Decision**: Pin the popup's horizontal content-hugging priority to
`.defaultHigh`.
**Rationale**: Keeps the popup sized to its content so `makeRow`'s
flexible spacer, not the popup, absorbs the row's leftover width — the
same spacer-absorbs-slack layout `CheckboxView`'s row relies on, made
explicit here because a borderless `NSPopUpButton`'s default hugging
behavior is not guaranteed to match a bordered one's.
**Approved**: pending

**Decision**: Link the popup's accessibility title to the label via
`setAccessibilityTitleUIElement` rather than setting a separate
accessibility label string.
**Rationale**: Per the source's own comment, "the visible title label
sits beside the popup but AppKit doesn't associate them, so VoiceOver
would announce the popup with no name."
**Approved**: pending

**Decision**: Silently ignore a selected item whose `representedObject`
fails the cast to `Value` (**ignores-unresolvable-selection**).
**Rationale**: `guard let value = sender.selectedItem?.representedObject
as? Value else { return }` in `popupChanged(_:)` is the only handling in
source; this documents the actual, traceable behavior rather than
assuming an error-reporting path exists.
**Approved**: pending

**Decision**: Leave a `viewModel.value` that matches no choice's value
uncorrected in `syncSelection` (**leaves-unmatched-selection**).
**Rationale**: `firstIndex(where:)` returning `nil` skips the
`selectItem(at:)` call entirely; the source neither clears the selection
nor forces a default item, so the popup keeps whatever item AppKit
selected by default — this documents the observed behavior, not an
idealized fallback.
**Approved**: pending

**Decision**: Unconditionally overwrite `viewModel.onChange` with the
component's own `syncSelection` handler at construction, rather than
composing with any handler already registered on that view model
(**replaces-onchange-handler**).
**Rationale**: `viewModel.onChange = { [weak self] _ in
self?.syncSelection() }` is plain closure-property assignment; the source
has no list- or token-based observer mechanism to compose with instead,
so a second observer of the same view model silently loses its handler.
Recorded here as an explicit, approved trade-off rather than left as an
undocumented trap in edge-case prose.
**Approved**: pending

**Decision**: Force a fatal error from both `init(coder:)` and the
frame-only `init(frame:)`, leaving the `viewModel`-taking initializer as
the only usable one.
**Rationale**: The view has no meaningful default state — it cannot
render a title, a choice list, or a value without a `viewModel` — so both
inherited `NSView` initializers that could construct it without one are
intentionally disabled rather than left to produce a half-configured row.
**Approved**: pending
