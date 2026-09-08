import AppKit
import Foundation

/// Hosts of `MultiTabbedViewController` implement this protocol to react to user
/// actions on any edge's tab bar — adding new tabs, switching tabs, closing
/// tabs, reordering tabs. Per-tab callbacks name the `Edge` whose bar fired
/// the event so a host with multiple enabled edges can route accordingly.
@MainActor
public protocol MultiTabbedViewControllerDelegate: AnyObject {

    /// User triggered "New Tab" (e.g. via the File menu). The tab count is
    /// global across edges: the host should build a content view controller
    /// per enabled edge and call `addTab(_:on:)` for each, keeping every
    /// enabled edge at the same tab count.
    func multiTabbedViewControllerNeedsNewTab(_ controller: MultiTabbedViewController)

    /// The user picked the tab on `edge` — by clicking its bar, or by closing
    /// the tab next to it and being handed the neighbour. **Not** the
    /// exhaustive "the selection moved" hook: a fallback activation after an
    /// edge is disabled, and the first tab arriving on an empty edge, both
    /// change the active tab without ever reaching here. Implement
    /// `activeTabDidChange` for that.
    func multiTabbedViewController(_ controller: MultiTabbedViewController, didSelectTab id: UUID, on edge: Edge)

    /// The active tab changed, however it changed — a click, `selectTab(id:on:)`,
    /// a fallback activation after a close, or the first tab arriving on an
    /// empty edge. Deliberately separate from `didSelectTab`, which means "the
    /// user picked this tab" and carries the heavier duties a host attaches to
    /// that (restoring focus, persisting). A host that only needs to know
    /// *which pane is in front now* implements this one and nothing else.
    func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        activeTabDidChange id: UUID,
        on edge: Edge
    )

    /// User clicked the close button on a tab on `edge`. The host can veto
    /// by simply not calling `removeTab(id:)` in response. By default the
    /// host should honor the request unless this is the last tab on that
    /// edge.
    func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        didRequestCloseTab id: UUID,
        on edge: Edge
    )

    /// User dragged a tab on `edge` to a new position within that edge.
    /// Already applied to the edge's tab list.
    func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        didReorderTab id: UUID,
        to index: Int,
        on edge: Edge
    )
}

extension MultiTabbedViewControllerDelegate {
    public func multiTabbedViewControllerNeedsNewTab(_ controller: MultiTabbedViewController) {}
    public func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        didSelectTab id: UUID,
        on edge: Edge
    ) {}
    public func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        activeTabDidChange id: UUID,
        on edge: Edge
    ) {}
    public func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        didRequestCloseTab id: UUID,
        on edge: Edge
    ) {
        controller.removeTab(id: id)
    }
    public func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        didReorderTab id: UUID,
        to index: Int,
        on edge: Edge
    ) {}
}
