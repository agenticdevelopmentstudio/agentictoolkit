<!-- leaf: implement-general-view-2/permission-row-view--test-vectors · source: permission-row-view.md -->

# PermissionRowView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| permission-row-001 | renders-title-from-permission | Construct with `permission: .accessibility` | `titleLabel` text is exactly `"Accessibility"`. |
| permission-row-002 | renders-title-from-permission | Construct with `permission: .automation(targetBundleID: "com.googlecode.iterm2")` where no app with that bundle id is installed | `titleLabel` text is `"Automation — com.googlecode.iterm2"` (falls back to the raw bundle id). |
| permission-row-003 | renders-description-from-permission | Construct with `permission: .keychain(service: "Claude Code-credentials")` | Description label text reads `Lets this app read the "Claude Code-credentials" item in your keychain directly, instead of asking another tool for it.` |
| permission-row-004 | renders-icon-from-permission | Construct with `permission: .microphone` | The `NSImageView` found among the row's `subviews` resolves the SF Symbol named `mic`, reports a `symbolConfiguration` of point size 16 / weight regular, and has `contentTintColor == .secondaryLabelColor`. |
| permission-row-005 | initial-status-is-checking | Construct a row, do not call `refresh()` | `statusText == "Checking…"`. |
| permission-row-006 | refresh-queries-checker | Stub `checker.status(_:)` to return `.granted`; call `await row.refresh()` | `statusText == "Granted"`. |
| permission-row-007 | cancelled-refresh-does-not-apply | Start `row.refresh()` inside a `Task`, cancel the task before `checker.status(_:)` returns, then `await` the task | `statusText` remains `"Checking…"`. |
| permission-row-008 | granted-status-appearance | `checker.status(_:)` returns `.granted`; `await row.refresh()` | `statusText == "Granted"`; `statusDot.layer?.backgroundColor == NSColor.systemGreen.cgColor`. |
| permission-row-009 | denied-status-appearance | `checker.status(_:)` returns `.denied`; `await row.refresh()` | `statusText == "Not Granted"`; `statusDot.layer?.backgroundColor == NSColor.systemOrange.cgColor`. |
| permission-row-010 | undetermined-status-appearance | `checker.status(_:)` returns `.undetermined`; `await row.refresh()` | `statusText == "Unknown"`; `statusDot.layer?.backgroundColor == NSColor.secondaryLabelColor.cgColor`. |
| permission-row-011 | status-conveyed-by-text-and-color | Refresh a row through all three statuses in turn | For each status, both `statusText` and `statusDot`'s color differ from the other two statuses — no two statuses share the same text or the same color. |
| permission-row-012 | granted-button-title | `permission: .keychain(service:)`; `checker.status(_:)` returns `.granted`; `await row.refresh()` | `actionTitle == "Open Settings"`. |
| permission-row-013 | ungranted-button-title | `permission: .keychain(service: "Claude Code-credentials")`; `checker.status(_:)` returns `.denied`, then separately `.undetermined`; `await row.refresh()` on each | Both rows' `actionTitle == "Allow…"`. |
| permission-row-014 | button-width-fits-widest-title | Construct two rows with different permissions | Both rows' action buttons report the same `frame.width`, equal to the fitting width of the longer of `"Open Settings"` / `"Allow…"`. |
| permission-row-015 | action-carries-displayed-status | `checker.status(_:)` returns `.denied`; `await row.refresh()`; call `row.performActionForTesting()` | `onAction` is invoked with `(permission, .denied)`. |
| permission-row-016 | action-button-has-stable-identifier | Construct with `permission: .location` | The action button's accessibility identifier is `"permission.location.action"`. |
| permission-row-017 | row-has-no-accessibility-identifier | Construct any row | The row `NSView` itself is not an accessibility element and has no accessibility identifier set. |
| permission-row-018 | minimum-row-height | Construct any row and let Auto Layout resolve | Resolved height is `>= 72` points. |
| permission-row-019 | card-appearance | Construct any row | `wantsLayer == true`; `layer?.cornerRadius == 8`; `layer?.borderWidth == 0.5`; `layer?.backgroundColor == NSColor.white.withAlphaComponent(0.03).cgColor`; `layer?.borderColor == NSColor.white.withAlphaComponent(0.06).cgColor`. |
| permission-row-020 | keyboard-activates-action | Construct any row, move keyboard focus to the action button (for example via `makeFirstResponder`), then perform its key equivalent (Space/Return) | `onAction` is invoked the same way it is by `performActionForTesting()` or a mouse click, since `actionButton` is an unmodified `NSButton`. |
| permission-row-021 | pre-refresh-action-enabled | Construct a row, do not call `refresh()`, then call `row.performActionForTesting()` | `actionButton.isEnabled == true` throughout, and `onAction` is invoked with `(permission, .undetermined)`. |
