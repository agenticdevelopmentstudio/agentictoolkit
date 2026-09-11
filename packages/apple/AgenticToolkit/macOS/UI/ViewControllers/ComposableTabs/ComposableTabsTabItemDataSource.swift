import AgenticToolkitCore
import AppKit

/// Supplies what each tab shows in the edge bar. The window controller owns
/// the tabs; the project controller owns what they mean, so it answers this.
@MainActor
public protocol ComposableTabsTabItemDataSource: AnyObject {
    func composableTabsWindowController(
        _ controller: ComposableTabsWindowController,
        tabItemFor record: TabRecord,
        on edge: Edge
    ) -> TabItem
}
