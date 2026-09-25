import AgenticToolkitHubService
import AgenticDeveloperToolkitUI
import AgenticToolkitHTDV

/// Spec §5.6: the "Not a member" fallback pane. The workspace picker in the
/// header stays available so the user can choose another workspace.
public enum NotMemberCopy {
    public static let title = "Not a member"
    public static func body(slug: String) -> String {
        "This account is not a member of “\(slug)”. Choose another workspace."
    }
}

#if canImport(AppKit)
import AppKit

public final class NotMemberViewController: NSViewController {
    private let slug: String

    public init(slug: String) {
        self.slug = slug
        super.init(nibName: nil, bundle: nil)
        title = NotMemberCopy.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func loadView() {
        let titleLabel = ThemedLabel(string: NotMemberCopy.title, textRole: .title)
        // Wrapping, so it stays an `NSTextField` and takes the palette directly.
        let body = NSTextField(wrappingLabelWithString: NotMemberCopy.body(slug: slug))
        body.setAccessibilityIdentifier("not-member.message")
        body.alignment = .center
        body.observeTheme { body, palette in
            body.textColor = palette.secondaryTextColor
            body.font = palette.font(.body)
        }
        let stack = NSStackView(views: [titleLabel, body])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = ThemedBackgroundView(role: .windowBackground)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
        view = container
    }
}

#elseif canImport(UIKit)
import UIKit

public final class NotMemberViewController: UIViewController {
    private let slug: String

    public init(slug: String) {
        self.slug = slug
        super.init(nibName: nil, bundle: nil)
        title = NotMemberCopy.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.observeTheme { view, palette in view.backgroundColor = palette.windowBackgroundColor }
        let titleLabel = ThemedLabel(string: NotMemberCopy.title, textRole: .title)
        let body = UILabel()
        body.text = NotMemberCopy.body(slug: slug)
        body.numberOfLines = 0
        body.textAlignment = .center
        body.observeTheme { body, palette in
            body.textColor = palette.secondaryTextColor
            body.font = palette.font(.body)
        }
        let stack = UIStackView(arrangedSubviews: [titleLabel, body])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }
}
#endif
