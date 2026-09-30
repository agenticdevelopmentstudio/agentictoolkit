<!-- leaf: implement-general-controller/tab-pane-view-controller--test-vectors-part-2 · source: tab-pane-view-controller.md -->

# TabPaneViewController — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| tab-pane-039 | header-text; session-text; branch-visibility; summary-visibility; title-and-preferred-content-size | `reload()` called once with short content (agent `"C"`, no model, session `"s"`, branch `"b"`, no summary), then again after every field changes and grows past `maxWidth` | `agentLabel.stringValue` and `sessionLabel.stringValue`/`branchLabel.stringValue` follow the new values; `summaryLabel.isHidden` flips from `true` to `false` once a summary appears; `preferredContentSize.width` moves from `minWidth` to `maxWidth` between the two calls (per `testReloadTwiceFollowsChangedDataSourceValues`) |
