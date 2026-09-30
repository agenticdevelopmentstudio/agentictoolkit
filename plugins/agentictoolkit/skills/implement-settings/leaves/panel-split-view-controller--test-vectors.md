<!-- leaf: implement-settings/panel-split-view-controller--test-vectors · source: settings-panel-split-view-controller.md -->

# SettingsPanelSplitViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| settings-panel-split-view-controller-001 | exposes-descriptor | Construct with an explicit `SettingsPanelDescriptor(title: "Theme")` | `descriptor.title == "Theme"` |
| settings-panel-split-view-controller-002 | defaults-descriptor-when-omitted | Construct via `init(with: nil)` | `descriptor` is a `SettingsPanelDescriptor` whose `title == ""` |
| settings-panel-split-view-controller-003 | titles-sidebar-from-descriptor | Construct with `SettingsPanelDescriptor(title: "Theme")` | `sidebarTitle == "Theme"` |
| settings-panel-split-view-controller-004 | rejects-coder-initialization | Attempt `init?(coder:)` | The call traps with a fatal error; no instance is returned |
| settings-panel-split-view-controller-005 | acts-as-hostable-panel | Construct an instance and call `enclosingSplit.addPanel(instance)` on a separate, outer `SplitViewController` | The outer split accepts it without a compile or runtime error; the instance appears in the outer split's `panels` |
| settings-panel-split-view-controller-006 | returns-nil-help-content-by-default | Read `helpContent` on a plain (non-subclassed) instance | Returns `nil` |
| settings-panel-split-view-controller-007 | falls-back-help-content-through-inner-selection | Select an inner panel whose `effectiveHelpContent` is non-`nil` | `effectiveHelpContent` on this instance returns that same value |
| settings-panel-split-view-controller-008 | falls-back-help-content-through-inner-selection | No inner panel selected, and a subclass overrides `helpContent` to a non-`nil` value | `effectiveHelpContent` returns that overridden `helpContent` value |
| settings-panel-split-view-controller-009 | falls-back-help-content-through-inner-selection | An inner panel is selected, its `effectiveHelpContent` is `nil`, and a subclass overrides this panel's own `helpContent` to a non-`nil` value | `effectiveHelpContent` falls through the inner selection's `nil` and returns the subclass's overridden `helpContent` value |
| settings-panel-split-view-controller-010 | surfaces-empty-help-when-chain-exhausted | No inner panel is selected (or the inner selection's `effectiveHelpContent` is `nil`), and no subclass overrides `helpContent` | `effectiveHelpContent` evaluates `nil ?? nil` and returns `nil` |
| settings-panel-split-view-controller-011 | reports-no-additional-search-keywords | Read `searchKeywords` on a plain (non-subclassed) instance | Returns `[]` |
| settings-panel-split-view-controller-012 | narrows-detail-minimum-thickness | Read `detailMinimumThickness` | Returns `200` |
| settings-panel-split-view-controller-013 | fixes-content-sized-sidebar | Read `contentSizedSidebar` | Returns `true` |

**runs-on-main-actor** has no conformance vector: Swift's actor isolation
checking rejects construction or mutation from off the main actor at
compile time, so there is no runtime behavior left to assert — the
requirement stands on the compiler's own enforcement.
