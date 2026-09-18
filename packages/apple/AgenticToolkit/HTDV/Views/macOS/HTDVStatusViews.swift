#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AgenticDeveloperToolkitUI
import AppKit

/// Centered message + Retry button, shown in place of a rail's table when its load failed.
public final class HTDVErrorView: NSView {
    let messageLabel = NSTextField(wrappingLabelWithString: "")
    let retryButton = ThemedSecondaryButton(title: "Retry")
    var onRetry: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        messageLabel.alignment = .center
        // `observeTheme` rather than `ThemedLabel`: a wrapping label is the one
        // thing that class is not (it clips to a single line on purpose), and
        // an error message is the one place that wants to wrap.
        messageLabel.observeTheme { label, palette in
            label.textColor = palette.secondaryTextColor
            label.font = palette.font(.body)
        }
        messageLabel.setAccessibilityIdentifier("htdv.error.message")
        retryButton.target = self
        retryButton.action = #selector(retryTapped)
        retryButton.setAccessibilityIdentifier("htdv.error.retry")
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
        spinner.setAccessibilityIdentifier("htdv.loading")
        spinner.translatesAutoresizingMaskIntoConstraints = false
        // A spinning indicator is drawn by AppKit from the effective
        // appearance rather than from any colour property — there is nothing on
        // it to tint. What the palette *can* decide is whether it is drawn
        // light or dark, which is what its appearance carries.
        spinner.observeTheme { spinner, palette in
            spinner.appearance = palette.standardAppearance
        }
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
