import AppKit

import AgenticDeveloperToolkitUI

/// A VS Code-style breadcrumb strip above a document editor: the open file's
/// path, relative to the project root, laid out as a row of buttons separated
/// by chevrons.
///
/// Kept to pure path arithmetic and layout — no filesystem access here, ever
/// (see `components(for:)`). The one piece that touches disk is
/// `BreadcrumbPopoverViewController`, shown when a crumb is clicked.
@MainActor
public final class BreadcrumbView: NSView {

    private let rootURL: URL
    private let stack = NSStackView()

    /// The file the strip currently describes. `nil` clears the strip.
    public var fileURL: URL? {
        didSet { rebuild() }
    }

    /// Fires with the file a popover chose, or with a crumb's own directory
    /// when `selectCrumb(at:)` is called directly. The owner routes this
    /// straight into `DocumentEditorViewController.onOpenRequest` — choosing
    /// in the breadcrumb is the same as clicking in the tree.
    public var onSelect: ((URL) -> Void)?

    /// The crumb labels, root to leaf. Empty when there is no file.
    public private(set) var crumbTitles: [String] = []

    /// The directory each crumb represents, parallel to `crumbTitles`. The
    /// last entry (the file's own crumb) is the file's *containing* directory
    /// — the popover it opens lists the file's siblings.
    private var crumbDirectories: [URL] = []

    private var activePopover: NSPopover?

    public init(rootURL: URL) {
        self.rootURL = rootURL
        super.init(frame: .zero)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Reports crumb `index`'s directory through `onSelect`, exactly as if
    /// its popover had opened and a listener acted on the directory itself.
    /// Exists so the index-to-directory mapping is testable without showing
    /// a popover — the real click handler (`crumbClicked(_:)`) opens the
    /// popover instead of calling this.
    public func selectCrumb(at index: Int) {
        guard index >= 0, index < crumbDirectories.count else { return }
        onSelect?(crumbDirectories[index])
    }

    // MARK: - Path arithmetic

    private func rebuild() {
        crumbTitles = Self.titles(for: fileURL, rootURL: rootURL)
        crumbDirectories = Self.directories(for: fileURL, titles: crumbTitles)

        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, title) in crumbTitles.enumerated() {
            if index > 0 {
                stack.addArrangedSubview(Self.chevron())
            }
            stack.addArrangedSubview(crumbButton(title: title, index: index))
        }
    }

    private func crumbButton(title: String, index: Int) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(crumbClicked(_:)))
        button.tag = index
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.lineBreakMode = .byTruncatingMiddle
        button.accessibilityID("breadcrumb.crumb.\(index)")
        return button
    }

    private static func chevron() -> NSImageView {
        let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        let imageView = NSImageView(image: image ?? NSImage())
        imageView.symbolConfiguration = .init(pointSize: 9, weight: .regular)
        imageView.contentTintColor = .secondaryLabelColor
        return imageView
    }

    @objc private func crumbClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0, index < crumbDirectories.count else { return }
        presentPopover(for: crumbDirectories[index], relativeTo: sender)
    }

    private func presentPopover(for directory: URL, relativeTo anchor: NSView) {
        let controller = BreadcrumbPopoverViewController(directoryURL: directory) { [weak self] chosen in
            self?.activePopover?.close()
            self?.onSelect?(chosen)
        }
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 320)
        controller.onCancel = { [weak popover] in popover?.close() }
        activePopover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    /// The crumb labels for `url`, relative to `rootURL` — `["Sources", "App",
    /// "Main.swift"]` for a file three levels under the root. A file outside
    /// the root falls back to its own last path component, so the strip is
    /// never empty for a file that merely lives somewhere unexpected.
    private static func titles(for url: URL?, rootURL: URL) -> [String] {
        guard let url else { return [] }
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents
        else { return [url.lastPathComponent] }
        return Array(fileComponents.dropFirst(rootComponents.count))
    }

    /// The directory each of `titles` represents, computed straight from
    /// `url`'s own absolute path components rather than from `rootURL` — this
    /// keeps the fallback-outside-the-root case (a single crumb with no
    /// relation to `rootURL`) working with the same arithmetic. Crumb `i`
    /// (for `i` before the last) is the directory named by path components
    /// `0...i`; the last crumb is the file itself, so its directory is the
    /// one before it — the folder the popover lists its siblings from.
    private static func directories(for url: URL?, titles: [String]) -> [URL] {
        guard let url, !titles.isEmpty else { return [] }
        let allComponents = url.standardizedFileURL.pathComponents
        let start = allComponents.count - titles.count
        return titles.indices.map { index in
            let upTo = index == titles.count - 1 ? start + index : start + index + 1
            return directoryURL(from: allComponents, upTo: upTo)
        }
    }

    /// Joins `components[1..<count]` (component 0 is the leading `"/"`) back
    /// into an absolute file URL.
    private static func directoryURL(from components: [String], upTo count: Int) -> URL {
        let clamped = max(1, min(count, components.count))
        let path = "/" + components[1..<clamped].joined(separator: "/")
        return URL(fileURLWithPath: path)
    }
}
