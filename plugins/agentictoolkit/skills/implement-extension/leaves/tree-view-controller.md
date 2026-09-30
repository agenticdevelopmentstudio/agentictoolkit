<!-- leaf: implement-extension/tree-view-controller · source: extension-tree-view-controller.md -->

# ExtensionTreeViewController

## Overview

`ExtensionTreeViewController` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/Tree/ExtensionTreeViewController.swift`) is the pane a contributed **tree** view occupies: `ExtensionViewPlaceholderViewController`'s explanation until the extension registers a `TreeDataProvider` for the view, then an `NSOutlineView`-backed outline bound to that provider. It is `ContributedWebviewResolving`'s twin and deliberately a different shape — a webview panel is the app's own object handed to the extension, while a tree data provider is the extension's object that may not exist yet, so the answer arrives asynchronously through a `didResolve` callback rather than being returned.

The same file also defines `ExtensionTreeOutlineViewController`, the internal `NSViewController` that actually draws the tree once a data source has resolved: it pulls children from the provider lazily (never asking for a branch nobody opens), caches every answer in an `ExtensionTreeRowTable` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/Tree/ExtensionTreeRowTable.swift`) so rows keep their object identity — and therefore their disclosure and selection — across refreshes, bounds each `getChildren` ask with a wall-clock budget, and reports the user's selection, expansion, activation and visibility back through `ExtensionTreeDataSource` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionTreeDataSource.swift`). Both classes are documented together here because they live in one file and one is the other's sole means of appearing on screen; `ExtensionViewPlaceholderViewController`, `ExtensionTreeRowTable` and `ExtensionTreeDataSource` are collaborators consulted for grounding but are out of this recipe's scope.

