<!-- leaf: implement-general-view-2/permission-row-view--states · source: permission-row-view.md -->

# PermissionRowView

## States

| State | Appearance change |
|-------|------------------|
| Default (constructed, before first `refresh()`) | `statusLabel` reads `"Checking…"` (its initial `NSTextField(labelWithString:)` value); `statusDot`'s layer has no background color assigned yet (only `apply(status:)` sets one); `actionButton.title` already reads `permission.actionTitle`, set unconditionally in `buildLayout()` independent of any status read. |
| Granted | `statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor`; `statusLabel.stringValue = "Granted"`, `textColor = .systemGreen`; `actionButton.title = "Open Settings"`. |
| Denied | `statusDot.layer?.backgroundColor = NSColor.systemOrange.cgColor`; `statusLabel.stringValue = "Not Granted"`, `textColor = .systemOrange`; `actionButton.title = permission.actionTitle`. |
| Undetermined | `statusDot.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor`; `statusLabel.stringValue = "Unknown"`, `textColor = .secondaryLabelColor`; `actionButton.title = permission.actionTitle`. |
| Pressed | Not applicable to the row itself: the row is not a control. The action button's own pressed appearance is `NSButton`'s default `.rounded` bezel highlight, unstyled by `PermissionRowView`. |
| Disabled | Not implemented in source: `isEnabled` is never set on `actionButton`, the row, or any subview. The button stays interactive in every status, including before the first `refresh()` completes — pressing it then reports `.undetermined`, `displayedStatus`'s initial value. |
| Focused | Not styled by `PermissionRowView`: any focus ring on the action button when tabbed to is `NSButton`'s own native `NSControl` focus appearance. |
| Loading | Same as "Default (constructed, before first `refresh()`)" above — `PermissionRowView` has one pre-refresh state, shown as `"Checking…"`, not a distinct spinner or progress indicator. |
