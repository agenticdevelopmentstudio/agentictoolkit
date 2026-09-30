<!-- leaf: implement-settings/card-views--states · source: settings-card-views.md -->

# Settings Card Views

## States

| State | Appearance change |
|-------|------------------|
| Default | `SettingsGroup`/`SettingsCard`/`SettingsCardRow`/`SettingsCardDivider` render exactly the static appearance described above; there is no other visual state for any of them. `SettingsSearchField` shows the wrapped field's placeholder or current `text`. |
| Pressed | Not applicable: none of the six APIs wires a target/action, gesture recognizer, or tap handler of its own. `SettingsSearchField`'s clear button and magnifier icon are `NSSearchField`'s native chrome, not code in this file. |
| Disabled | Not applicable: the source never reads or sets `isEnabled` (or a dimmed equivalent) on any of the six APIs. |
| Focused | Not applicable for `SettingsGroup`/`SettingsCard`/`SettingsCardRow`/`SettingsCardDivider`, which accept no keyboard focus. For `SettingsSearchField`, no custom focus styling is coded — wrapping a real `NSSearchField` (via `ThemedSearchField`) means the system supplies the native focus ring automatically, which the source's own comment gives as the explicit reason not to hand-roll the control. |
| Loading | Not applicable: none of the six APIs performs asynchronous work or defines a loading indicator. |
