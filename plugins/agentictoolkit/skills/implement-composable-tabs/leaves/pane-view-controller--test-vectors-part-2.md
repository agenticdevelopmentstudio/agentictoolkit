<!-- leaf: implement-composable-tabs/pane-view-controller--test-vectors-part-2 · source: composable-tabs-pane-view-controller.md -->

# ComposableTabsPaneViewController — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ctpvc-050 | contains-first-responder-hierarchy-walk | View loaded; window's first responder is a subview nested inside this pane's view | `containsFirstResponder` returns `true` |
| ctpvc-050b | contains-first-responder-hierarchy-walk | View loaded; window's first responder belongs to a different pane | `containsFirstResponder` returns `false` |
| ctpvc-051 | title-bar-bottom-constant | Read `ComposableTabsPaneViewController.titleBarBottom` | Equals 28 (2pt border inset + 26pt title bar height) |
| ctpvc-052 | active-pane-cue-is-color-only | Compare the backdrop's drawn border for the active pane vs. an inactive one | `borderWidth` is 2 in both; only `borderColor` differs |
