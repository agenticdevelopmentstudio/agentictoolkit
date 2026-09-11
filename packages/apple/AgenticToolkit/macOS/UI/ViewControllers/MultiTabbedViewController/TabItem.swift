import AppKit

/// What a tab shows in the edge bar: a plain title, or a view controller
/// that draws itself and reports its size through `preferredContentSize`.
public enum TabItem {
    case title(String)
    case viewController(NSViewController)

    @MainActor
    public var title: String {
        switch self {
        case let .title(title): title
        case let .viewController(controller): controller.title ?? ""
        }
    }
}

/// A view controller hosted as a bar item adopts this so the bar can show
/// selection and let the item ask to close, exactly as `TabButton` does.
///
/// Public because `TabItem.viewController` is public: a conforming type is
/// this protocol's whole contract, so a consumer outside the framework has
/// to be able to adopt it. Without `public` here, an outside pane compiles
/// and installs but the two `as? TabBarHostedItem` casts inside `TabBarView`
/// can never succeed, so it silently never highlights and never closes.
@MainActor
public protocol TabBarHostedItem: AnyObject {
    var isHighlighted: Bool { get set }
    var onClose: (() -> Void)? { get set }
}

/// A hosted item that draws itself as one card in a stack of them, and so needs
/// to know more than whether it is selected: how far it stands from whichever
/// item is.
///
/// Separate from `TabBarHostedItem` rather than folded into it because most
/// items have no use for the number — a plain title has no depth to draw — and
/// an item that ignored it would have to say so in code. The bar asks for this
/// with a cast, exactly as it asks for `TabBarHostedItem`.
@MainActor
public protocol TabBarStackedItem: TabBarHostedItem {
    /// Counted in items: 0 for the selected item itself, 1 for either
    /// neighbour, and on outward.
    var stackDepth: Int { get set }
}
