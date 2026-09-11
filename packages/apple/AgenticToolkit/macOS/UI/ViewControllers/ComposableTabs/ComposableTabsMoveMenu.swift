import AgenticDeveloperToolkitUI
import AppKit

/// The four ways a pane can move, as menu items.
///
/// Two places offer the move now — the arrange overlay's pull-down and the
/// gear menu in every pane's title bar — and the labels, the arrows, the
/// identifiers and the rule for which of the four are legal are one piece of
/// knowledge, not two (`dry`). A second spelling is a second place to miss when
/// a direction is added or a name changes.
///
/// An object rather than a free function because `NSMenuItem` holds its target
/// unowned: something has to outlive the menu, and the owner of the menu is the
/// natural thing to be it.
@MainActor
final class ComposableTabsMoveMenu: NSObject {

    typealias Direction = ComposableTabsViewController.Direction

    /// Re-read every time items are built; the tree changes under the caller
    /// each time any pane moves, so a set captured once would be stale.
    var availableDirections: () -> Set<Direction> = { [] }

    var onMove: ((Direction) -> Void)?

    /// One item per direction, in `Direction.allCases` order, each enabled only
    /// if the move is currently legal.
    ///
    /// `accessibilityPrefix` is the caller's, because the two menus are two
    /// different surfaces to a UI test: the overlay's items have always been
    /// `composable-tabs.arrange.move.<name>` and stay that way.
    func makeItems(accessibilityPrefix: String) -> [NSMenuItem] {
        let available = availableDirections()
        return Direction.allCases.map { direction in
            let item = NSMenuItem(
                title: direction.movementName,
                action: #selector(moveSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = DirectionBox(direction)
            item.isEnabled = available.contains(direction)
            item.image = NSImage(
                systemSymbolName: direction.arrowSymbolName,
                accessibilityDescription: direction.movementName)
            item.accessibilityID("\(accessibilityPrefix).\(direction.movementName.lowercased())")
            return item
        }
    }

    /// `representedObject` is `Any?`, and a bare enum bridges to `NSNull` under
    /// Swift 6's stricter object-conversion rules; boxing keeps it a real
    /// reference.
    private final class DirectionBox: NSObject {
        let direction: Direction
        init(_ direction: Direction) { self.direction = direction }
    }

    @objc private func moveSelected(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? DirectionBox else { return }
        onMove?(box.direction)
    }
}
