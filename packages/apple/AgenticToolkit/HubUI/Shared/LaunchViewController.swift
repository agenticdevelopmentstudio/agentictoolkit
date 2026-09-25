import AgenticToolkitHubService
import AgenticDeveloperToolkitUI
import AgenticToolkitHTDV

#if canImport(AppKit)
import AppKit

/// Spinner while launching/loading a workspace; message + Retry on error.
public final class LaunchViewController: NSViewController {
    private let spinner = NSProgressIndicator()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let retryButton = ThemedActionButton(title: "Retry")
    private var retryAction: (@MainActor () -> Void)?

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func loadView() {
        spinner.setAccessibilityIdentifier("launch.spinner")
        messageLabel.setAccessibilityIdentifier("launch.error.message")
        retryButton.setAccessibilityIdentifier("launch.error.retry")
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 4
        // A wrapping label is the one thing `ThemedLabel` is not, so it takes
        // its colour and font from the palette directly.
        messageLabel.observeTheme { label, palette in
            label.textColor = palette.secondaryTextColor
            label.font = palette.font(.body)
        }
        retryButton.target = self
        retryButton.action = #selector(retryTapped)
        let stack = NSStackView(views: [spinner, messageLabel, retryButton])
        stack.orientation = .vertical
        stack.spacing = 12
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
        showLoading()
    }

    public func showLoading() {
        _ = view
        spinner.startAnimation(nil)
        messageLabel.stringValue = ""
        messageLabel.isHidden = true
        retryButton.isHidden = true
        retryAction = nil
    }

    public func showError(_ message: String, retry: @escaping @MainActor () -> Void) {
        _ = view
        spinner.stopAnimation(nil)
        messageLabel.stringValue = message
        messageLabel.isHidden = false
        retryButton.isHidden = false
        retryAction = retry
    }

    @objc private func retryTapped() {
        retryAction?()
    }
}

#elseif canImport(UIKit)
import UIKit

public final class LaunchViewController: UIViewController {
    private let spinner = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()
    private let retryButton = UIButton(configuration: .filled())
    private var retryAction: (@MainActor () -> Void)?

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.observeTheme { view, palette in view.backgroundColor = palette.windowBackgroundColor }
        spinner.hidesWhenStopped = true
        spinner.observeTheme { spinner, palette in spinner.color = palette.accentColor }
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.observeTheme { label, palette in
            label.textColor = palette.secondaryTextColor
            label.font = palette.font(.body)
        }
        // The filled configuration is what draws this button's look, so it
        // stays a `UIButton` and takes the accent as its fill.
        retryButton.observeTheme { button, palette in
            button.configuration?.baseBackgroundColor = palette.accentColor
            button.configuration?.baseForegroundColor = palette.onAccentTextColor
        }
        retryButton.configuration?.title = "Retry"
        retryButton.addAction(UIAction { [weak self] _ in self?.retryAction?() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [spinner, messageLabel, retryButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        showLoading()
    }

    public func showLoading() {
        loadViewIfNeeded()
        spinner.startAnimating()
        messageLabel.text = nil
        messageLabel.isHidden = true
        retryButton.isHidden = true
        retryAction = nil
    }

    public func showError(_ message: String, retry: @escaping @MainActor () -> Void) {
        loadViewIfNeeded()
        spinner.stopAnimating()
        messageLabel.text = message
        messageLabel.isHidden = false
        retryButton.isHidden = false
        retryAction = retry
    }
}
#endif
