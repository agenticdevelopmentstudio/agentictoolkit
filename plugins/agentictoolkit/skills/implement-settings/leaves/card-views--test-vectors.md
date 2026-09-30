<!-- leaf: implement-settings/card-views--test-vectors · source: settings-card-views.md -->

# Settings Card Views

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| settings-card-views-001 | group-caption | Construct `SettingsGroup("Section") { Text("Row") }` | A caption view showing "Section" in `.caption` font and `secondaryText` color appears above the card |
| settings-card-views-002 | group-omits-caption-when-title-absent | Construct `SettingsGroup { Text("Row") }` (no title) | No caption view is rendered; only the card appears |
| settings-card-views-003 | group-caption-spacing | Construct `SettingsGroup("Section") { Text("Row") }` and measure the rendered layout | The vertical gap between the caption's bottom edge and the card's top edge is 6pt |
| settings-card-views-004 | group-stretches-full-width | Place `SettingsGroup` in a container 400pt wide | The rendered `SettingsGroup` occupies the full 400pt width, leading-aligned |
| settings-card-views-005 | group-title-not-auto-localized | Add a `Localizable.strings` entry mapping the literal string passed as `title` to a different translation, then render `SettingsGroup(titleVariable) { … }` where `titleVariable` is a `String` variable holding that same text | The caption displays the original untranslated string, not the localized entry |
| settings-card-views-006 | card-fills-rounded-elevated-surface | Render `SettingsCard { Color.red }` under a known theme | The card's background pixel color matches the theme's `elevatedSurface` value, and its clip shape is `RoundedRectangle(cornerRadius: 10, style: .continuous)` (or matches a snapshot-test baseline for the rendered corner) |
| settings-card-views-007 | card-stretches-full-width | Place `SettingsCard` in a container 400pt wide | The rendered card occupies the full 400pt width, leading-aligned |
| settings-card-views-008 | card-row-insets-content | Render `SettingsCardRow { Text("Label") }` inside a card of known width | The label's frame is inset 14pt from each side edge and 9pt from top and bottom |
| settings-card-views-009 | card-row-stretches-full-width | Place `SettingsCardRow` in a container 400pt wide | The rendered row occupies the full 400pt width, leading-aligned |
| settings-card-views-010 | divider-renders-hairline | Render `SettingsCardDivider()` under a known theme | A horizontal bar exactly 1pt tall appears, filled with the theme's `divider` color |
| settings-card-views-011 | divider-insets-from-leading-edge | Render `SettingsCardDivider()` inside a card 400pt wide | The hairline starts 14pt from the leading edge and extends to the trailing edge with no trailing inset |
| settings-card-views-012 | panel-inset-pads-uniformly | Apply `.settingsPanelInset()` to a 300×300pt view | The modified view's content is inset 20pt on all four sides |
| settings-card-views-013 | search-field-wraps-native-control | Instantiate `SettingsSearchField("Search", text: $binding)` and inspect the produced `NSView` hierarchy | The produced view is (or contains) a `ThemedSearchField` instance, a subclass of `NSSearchField` |
| settings-card-views-014 | search-field-filters-live | Inspect the `ThemedSearchField` created by `makeNSView` | `sendsWholeSearchString == false` and `sendsSearchStringImmediately == true` |
| settings-card-views-015 | search-field-writes-through-binding | Type a character into the live field so its search action fires | The bound `text` value updates to the field's new `stringValue` |
| settings-card-views-016 | search-field-avoids-cursor-jump | Place the insertion point mid-string in the field, then trigger `updateNSView` with a `text` value equal to the field's current `stringValue` | The field's `stringValue` is not reassigned and the insertion point does not move |
| settings-card-views-017 | search-field-coordinator-binding | Re-render the SwiftUI parent with a new `text` binding instance (forcing `updateNSView`), then trigger the field's search action | The new binding's backing value updates to the field's current `stringValue`; the binding captured at `makeCoordinator` is left unchanged |
| settings-card-views-018 | search-field-sizes-to-fitting-height | Call `sizeThatFits` with a proposal of `width: 200, height: nil` | The returned height equals the wrapped field's `fittingSize.height`, and the returned width is 200 |
| settings-card-views-019 | search-field-placeholder-not-auto-localized | Add a `Localizable.strings` entry mapping the literal string passed as `placeholder` to a different translation, then construct `SettingsSearchField(placeholderVariable, text: $binding)` | The field's `placeholderString` shows the original untranslated string |
| settings-card-views-020 | card-stays-internal | From a Swift file in a different module that imports the defining module, attempt to reference `SettingsCard` by name | Compilation fails: the symbol is inaccessible from outside the defining module |
| settings-card-views-021 | search-field-stays-internal | From a Swift file in a different module that imports the defining module, attempt to reference `SettingsSearchField` by name | Compilation fails: the symbol is inaccessible from outside the defining module |
