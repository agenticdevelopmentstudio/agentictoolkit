#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

/// Horizontal row of "Root › Level › Level" buttons; clicking one re-selects that level's item.
public final class HTDVBreadcrumbBar: NSView {
    public var onSelectCrumb: (Int) -> Void = { _ in }
    private(set) var buttons: [NSButton] = []
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public func apply(titles: [String]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons = []
        for (index, title) in titles.enumerated() {
            if index > 0 {
                let separator = NSTextField(labelWithString: "›")
                separator.textColor = .tertiaryLabelColor
                stack.addArrangedSubview(separator)
            }
            let button = NSButton(title: title, target: self, action: #selector(crumbTapped(_:)))
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.tag = index
            button.font = index == titles.count - 1
                ? .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
                : .systemFont(ofSize: NSFont.smallSystemFontSize)
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
    }

    @objc private func crumbTapped(_ sender: NSButton) { onSelectCrumb(sender.tag) }
}
#endif
