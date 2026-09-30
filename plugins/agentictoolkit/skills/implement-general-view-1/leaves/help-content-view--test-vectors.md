<!-- leaf: implement-general-view-1/help-content-view--test-vectors · source: help-content-view.md -->

# HelpContentView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| help-content-view-001 | fixed-help-heading | Construct `HelpContentView()` | A subview with `stringValue == "Help"` exists, pinned 20pt from the view's top and leading edges, outside the scroll view's document |
| help-content-view-002 | independently-scrolling-content | Call `setHelp` with topics whose combined height exceeds the view's frame, then scroll the document | The heading label's frame is unchanged while the visible topic content scrolls |
| help-content-view-003 | topic-groups | `setHelp(HelpContent(topics: [Topic(title: "A", body: "a"), Topic(title: "B", body: "b")]))` | The panel contains exactly 2 `GroupView`s in order, titled "A" then "B", each with one `ExplanationView` whose text matches the topic's `body` |
| help-content-view-004 | empty-state | `setHelp(nil)` | The panel contains exactly 1 `GroupView` titled "No Help Yet" with one `ExplanationView` reading the fixed empty-state sentence |
| help-content-view-005 | empty-state | `setHelp(HelpContent(topics: []))` | Same result as help-content-view-004 |
| help-content-view-006 | wholesale-replacement | Call `setHelp` with topic set A, then call it again with topic set B | After the second call, none of topic set A's `GroupView`/`ExplanationView` instances remain in the panel; only topic set B's are present |
| help-content-view-007 | scroll-reset | Call `setHelp` with tall content, scroll to the bottom, then call `setHelp` again with new content | The scroll view's visible origin is back at the top immediately after the second call returns |
| help-content-view-008 | theme-application, window-background | Construct `HelpContentView()` while Theme A is active | `layer.backgroundColor == ThemeA.windowBackgroundColor.cgColor` (not a distinct or hardcoded color); `titleLabel.font == ThemeA.font(.heading)`; `titleLabel.textColor == ThemeA.primaryTextColor` |
| help-content-view-009 | theme-application | With the view constructed under Theme A, switch the active theme to Theme B | All three properties from help-content-view-008 update to Theme B's values without re-constructing the view |
| help-content-view-010 | coder-init-unavailable | Compile `HelpContentView(coder: someCoder)` at any call site | The line fails to compile — `init(coder:)` is marked `@available(*, unavailable)`. This is a compile-time/availability check, not a runtime trap, and is not automatable via a runtime test harness. |
