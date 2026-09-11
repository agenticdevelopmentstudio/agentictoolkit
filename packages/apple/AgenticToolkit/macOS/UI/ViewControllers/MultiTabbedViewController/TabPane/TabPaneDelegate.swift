import AppKit

/// Selection and close are the tab bar's business (through `TabBarHostedItem`);
/// the delegate only supplies the context menu.
@MainActor
public protocol TabPaneDelegate: AnyObject {
    func tabPane(_ pane: TabPaneViewController, contextMenuFor event: NSEvent) -> NSMenu?
}
