<!-- leaf: implement-settings/panel-split-view-controller--part-2 · source: settings-panel-split-view-controller.md -->

# SettingsPanelSplitViewController — continued (part 2)

## Design Decisions

**Decision**: Override `detailMinimumThickness` to `200` points rather than
inheriting `SplitViewController`'s `400`pt default.
**Rationale**: Per the doc comment on
`SettingsPanelSplitViewController.detailMinimumThickness`, "a modest floor
so the nested detail (the sub-panel content) can't be squeezed to a
sliver. It stays below the outer detail's own floor, so it caps the inner
content rather than compounding the window's minimum width."
**Approved**: pending

**Decision**: Override `contentSizedSidebar` to `true` rather than
inheriting `SplitViewController`'s draggable, autosaved default.
**Rationale**: Per the doc comment on
`SettingsPanelSplitViewController.contentSizedSidebar`, "nested topic lists
are content-sized and unified to one width by the parent split, so
switching between sibling panels never shifts the inner divider and every
title stays fully disclosed."
**Approved**: pending

**Decision**: Redeclare `helpContent`, `effectiveHelpContent`, and
`searchKeywords` on this class rather than relying solely on
`ComposableSettingsPanel`'s protocol-extension defaults.
**Rationale**: Per the doc comment on
`SettingsPanelSplitViewController.helpContent` (citing the same reasoning
documented on the sibling `SettingsPanelViewController.helpContent`), a
protocol extension's default is bound at the point of conformance; a
subclass override reachable only through the extension default would be
invisible through the `any ComposableSettingsPanel` existential the
enclosing split holds. Redeclaring the properties on the class keeps
subclass overrides reachable.
**Approved**: pending
