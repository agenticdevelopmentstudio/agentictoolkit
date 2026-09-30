<!-- leaf: implement-extension-host-core-1/extensions-contributed-views · source: extension-host-core-extensions-contributed-views.md -->

# ContributedViewsBuilder

## Overview

`ContributedViews.swift` (`packages/apple/AgenticToolkit/Core/Extensions/ContributedViews.swift`) defines the data this host keeps for a VS Code extension's `contributes.views` and `contributes.viewsContainers` manifest entries, and the pure, Foundation-only `ContributedViewsBuilder.build(from:manifest:)` function that produces them from an already-decoded `ExtensionManifest.Contributions`. Nothing here renders anything: a `ContributedViewContainer` is recorded but never drawn, because nothing in this host resolves a container yet (Ruling FD). A `ContributedView` is resolved as far as a host without a real VS Code extension host can resolve it — its icon is turned into an SF Symbol name where a mapping exists, its target container decides one Boolean (`preferredAxisIsVertical`), and everything this host cannot honor exactly (an unevaluated `when` clause, an icon with no symbol equivalent, a field the decoder could not read, a repeated view id, a container-less target) is recorded as a `ContributedViewNote` rather than silently dropped or thrown. `CodiconSymbols` is the fixed, hand-built table this file consults to answer the icon question; it is a lookup table, not a transformation, because the two icon vocabularies (VS Code codicons and SF Symbols) have no algorithmic relationship.

