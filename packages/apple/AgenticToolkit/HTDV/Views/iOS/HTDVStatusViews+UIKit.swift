#if canImport(UIKit)
import AgenticDeveloperToolkitUI
import UIKit

/// Centered message + Retry button.
public final class HTDVErrorView: UIView {
    let messageLabel = UILabel()
    let retryButton = UIButton(type: .system)
    var onRetry: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        // A wrapping label is the one thing `ThemedLabel` is not, so it takes
        // its colour and font from the palette directly.
        messageLabel.observeTheme { label, palette in
            label.textColor = palette.secondaryTextColor
            label.font = palette.font(.body)
        }
        retryButton.setTitle("Retry", for: .normal)
        retryButton.observeTheme { button, palette in
            button.tintColor = palette.accentColor
            button.titleLabel?.font = palette.font(.button)
        }
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [messageLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// Centered spinner.
public final class HTDVLoadingView: UIView {
    let spinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.observeTheme { spinner, palette in spinner.color = palette.accentColor }
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override public var isHidden: Bool {
        didSet { isHidden ? spinner.stopAnimating() : spinner.startAnimating() }
    }
}
#endif
