<!-- leaf: implement-composable-tabs/add-pane-view-controller--states · source: composable-tabs-add-pane-view-controller.md -->

# ComposableTabsAddPaneViewController

## States

| State | Appearance change |
|-------|--------------------|
| Default (initial load) | "Add" popup lists all `choices` in order; "Where" popup lists Left/Right/Above/Below and selects "Right"; OK's enabled state is fixed from `!choices.isEmpty`. |
| Choices non-empty | OK button `isEnabled == true`. |
| Choices empty | OK button `isEnabled == false`; "Add" popup has zero items. |
| Selection changed (user) | The chosen popup item shows as selected; no other view updates in response — OK's enabled state does not react to the change. |
| Pressed | Not applicable — Cancel/OK use the stock `.rounded` `NSButton` bezel; source overrides no pressed/highlight rendering. |
| Focused | Not applicable — source sets no custom focus ring or explicit key-view loop; whichever control is focused uses AppKit's default focus-ring appearance and the default subview tab order. |
| Disabled | Applies only to OK, per "Choices empty" above; the disabled appearance is AppKit's stock dimmed bezel, not custom-drawn. |
| Loading | Not applicable — `choices` is supplied synchronously at `init`, and `loadView()` builds the whole view hierarchy synchronously; source defines no asynchronous or pending state. |
