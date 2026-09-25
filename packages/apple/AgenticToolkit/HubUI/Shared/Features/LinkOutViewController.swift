import AgenticToolkitHubService
import AgenticDeveloperToolkitUI
import AgenticToolkitHTDV
import Foundation

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

/// "This section opens on the web." with a button (spec §5.4 link-out rows).
public final class LinkOutViewController: NSViewController {
    public let url: URL
    private let paneTitle: String

    public init(title: String, url: URL) {
        self.paneTitle = title
        self.url = url
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func loadView() {
        let titleLabel = ThemedLabel(string: paneTitle, textRole: .title)
        let body = ThemedLabel(string: "This section opens on the web.", role: .secondaryText)
        let button = ThemedActionButton(
            title: "Open in Browser", style: .primary, target: self, action: #selector(open))
        let stack = NSStackView(views: [titleLabel, body, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = ThemedBackgroundView(role: .surface)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        view = container
    }

    @objc private func open() {
        NSWorkspace.shared.open(url)
    }
}

/// Placeholder for a detail feature whose module is not registered yet.
public final class UnavailableViewController: NSViewController {
    private let paneTitle: String

    public init(title: String) {
        self.paneTitle = title
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func loadView() {
        let label = ThemedLabel(string: RootDataSource.unavailableMessage, role: .secondaryText)
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = ThemedBackgroundView(role: .surface)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        view = container
    }
}

#elseif canImport(UIKit)
import UIKit

public final class LinkOutViewController: UIViewController {
    public let url: URL
    private let paneTitle: String

    public init(title: String, url: URL) {
        self.paneTitle = title
        self.url = url
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.observeTheme { view, palette in view.backgroundColor = palette.surfaceColor }
        let titleLabel = ThemedLabel(string: paneTitle, textRole: .title)
        let body = ThemedLabel(string: "This section opens on the web.", role: .secondaryText)
        let button = ThemedButton(title: "Open in Browser", primaryAction: UIAction { [url] _ in
            UIApplication.shared.open(url)
        })
        let stack = UIStackView(arrangedSubviews: [titleLabel, body, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

public final class UnavailableViewController: UIViewController {
    private let paneTitle: String

    public init(title: String) {
        self.paneTitle = title
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.observeTheme { view, palette in view.backgroundColor = palette.surfaceColor }
        let label = ThemedLabel(string: RootDataSource.unavailableMessage, role: .secondaryText)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
#endif
