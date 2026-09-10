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
@MainActor
protocol TabBarHostedItem: AnyObject {
    var isHighlighted: Bool { get set }
    var onClose: (() -> Void)? { get set }
}
