<!-- leaf: implement-general-view-2/path-view--test-vectors · source: path-view.md -->

# PathView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| path-view-001 | renders-path-non-wrapping-single-line | Construct the view | `label.cell?.wraps == false`; `label.maximumNumberOfLines == 1`; `label.cell?.usesSingleLineMode == false` |
| path-view-002 | truncates-middle | Construct the view | `label.lineBreakMode == .byTruncatingMiddle` |
| path-view-003 | retains-untruncated-path | `PathView(withPath: "/very/long/path/that/does/not/fit")`, constrain the view to a narrow width, and lay it out | The label's displayed glyphs are visibly truncated (the rendered string differs from `label.stringValue`, e.g. contains an ellipsis), while `view.path == "/very/long/path/that/does/not/fit"` and `label.toolTip == "/very/long/path/that/does/not/fit"` remain the full, untruncated string |
| path-view-004 | prefixes-optional-caption | `PathView(withPath: "/tmp/x", caption: "Folder")` | `label.stringValue == "Folder: /tmp/x"` |
| path-view-005 | omits-caption-when-absent | `PathView(withPath: "/tmp/x")` | `label.stringValue == "/tmp/x"` |
| path-view-006 | exposes-raw-path-as-tooltip | `PathView(withPath: "/tmp/x")` | `label.toolTip == "/tmp/x"` |
| path-view-007 | exposes-raw-path-as-tooltip | `PathView(withPath: "/tmp/x", caption: "Folder")` | `label.toolTip == "/tmp/x"` (not `"Folder: /tmp/x"`) |
| path-view-008 | exposes-raw-path-as-accessibility-value | `PathView(withPath: "/tmp/x")` | `label.accessibilityValue() as? String == "/tmp/x"` |
| path-view-009 | exposes-raw-path-as-accessibility-value | `PathView(withPath: "/tmp/x", caption: "Folder")` | `label.accessibilityValue() as? String == "/tmp/x"` (not `"Folder: /tmp/x"`) |
| path-view-010 | supports-text-selection | Construct the view, then inspect the label | `label.isSelectable == true`; `label.stringValue` equals the full display string (the caption-prefixed string when a caption is supplied, `path` alone otherwise) |
| path-view-011 | yields-width-to-container | Construct the view | `label.contentCompressionResistancePriority(for: .horizontal) == .defaultLow`; `label.contentHuggingPriority(for: .horizontal) == .defaultLow` |
| path-view-012 | fills-container-bounds | Construct the view, then lay it out inside a fixed-size superview | The label's resolved frame has zero inset from `PathView`'s frame on all four edges |
| path-view-013 | exposes-label-property | Construct the view, then access `.label` from outside the type | The property is accessible and returns the same `NSTextField` instance built during init |
| path-view-014 | exposes-path-property | Construct the view, then access `.path` from outside the type | The property is accessible and equals the string passed to `init(withPath:)` |
| path-view-015 | styles-as-secondary-caption | Construct the view | `label.font` equals the active theme's `.caption` font; `label.textColor` equals the active theme's `.secondaryText` color |
| path-view-016 | conforms-to-settings-view-protocol | Construct the view | The instance can be assigned to a `SettingsViewProtocol`-typed variable without a cast |
| path-view-017 | rejects-frame-only-initialization | Attempt `PathView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| path-view-018 | rejects-storyboard-instantiation | Attempt `PathView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| path-view-019 | prefixes-optional-caption | `PathView(withPath: "/tmp/x", caption: "")` | `label.stringValue == ": /tmp/x"` |
| path-view-020 | truncates-middle | `PathView(withPath: "/tmp/x", caption: "AVeryLongCaptionThatAloneExceedsTheAvailableWidth")`, then constrain the view narrower than the caption's own rendered width | The displayed, truncated glyphs elide into the caption itself, not only the path portion; `label.lineBreakMode == .byTruncatingMiddle` |

A UI-test note: verifying that selecting all and copying yields the full
label text on the system pasteboard requires pasteboard or UI-automation
access and cannot be asserted deterministically in a unit test; cover it in a
UI/integration test suite instead of a conformance vector.
