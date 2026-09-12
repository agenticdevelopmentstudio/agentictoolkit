import Foundation

/// Where a file the user picked in the File Browser should be shown.
///
/// `FileBrowserSelection.selectedNode` already says *what* the user picked;
/// it has no way to say *where* it should land — replace what the focused
/// editor is showing, open a new tab, or split a second editor in beside the
/// first. Clicking a file is `.current`; the context menu's three verbs
/// (`FileTreeOutlineViewController.makeContextMenu(for:)`) are the other two
/// plus `.current` again, spelled out explicitly rather than left implicit.
public enum DocumentDestination: Equatable {
    /// Replace what the focused editor in the focused tab is showing.
    case current
    /// A new tab with one editor, which becomes the focused tab.
    case newTab
    /// A second editor beside the focused one, in the focused tab.
    case toTheSide
}
