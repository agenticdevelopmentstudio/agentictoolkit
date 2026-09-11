import Foundation

/// Supplies everything a tab pane displays. The pane never computes any of
/// it; whoever vends the pane (a branch controller) answers these.
@MainActor
public protocol TabPaneDataSource: AnyObject {
    func tabPaneAgentName(_ pane: TabPaneViewController) -> String
    func tabPaneModelName(_ pane: TabPaneViewController) -> String?
    func tabPaneStatusSymbols(_ pane: TabPaneViewController) -> [TabPaneStatusSymbol]
    func tabPaneSessionName(_ pane: TabPaneViewController) -> String
    func tabPaneWorkingDirectory(_ pane: TabPaneViewController) -> URL
    func tabPaneBranch(_ pane: TabPaneViewController) -> String?
    func tabPaneSummary(_ pane: TabPaneViewController) -> String?
}
