#if canImport(UIKit)
import UIKit

public enum HTDVBadgeColorMapping {
    public static func uiColor(_ color: HTDVBadgeColor) -> UIColor {
        switch color {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .gray: .systemGray
        }
    }
}

/// Centered message + Retry button.
public final class HTDVErrorView: UIView {
    let messageLabel = UILabel()
    let retryButton = UIButton(type: .system)
    var onRetry: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.textColor = .secondaryLabel
        retryButton.setTitle("Retry", for: .normal)
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
