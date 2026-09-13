#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

/// Centered message + Retry button, shown in place of a rail's table when its load failed.
public final class HTDVErrorView: NSView {
    let messageLabel = NSTextField(wrappingLabelWithString: "")
    let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    var onRetry: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        retryButton.bezelStyle = .rounded
        retryButton.target = self
        retryButton.action = #selector(retryTapped)
        let stack = NSStackView(views: [messageLabel, retryButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func retryTapped() { onRetry() }
}

/// Centered indeterminate spinner.
public final class HTDVLoadingView: NSView {
    let spinner = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override public var isHidden: Bool {
        didSet { isHidden ? spinner.stopAnimation(nil) : spinner.startAnimation(nil) }
    }
}
#endif
