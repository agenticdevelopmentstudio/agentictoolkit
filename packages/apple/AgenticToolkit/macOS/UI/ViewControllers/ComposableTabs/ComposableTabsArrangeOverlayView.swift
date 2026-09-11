import AppKit

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// What a pane looks like while the user is arranging rather than working: the
/// content dimmed behind a scrim, and one small toolbar in the middle of it.
///
/// The scrim is a real view rather than an alpha on the content because it also
/// has to *swallow* the clicks — a terminal that kept taking keystrokes behind
/// the arrange toolbar would be a pane you can rearrange and type into at the
/// same time. It stays a subview of the pane's backdrop, so a click on it still
/// walks up to `ComposableTabsPaneBackgroundView` and selects the pane, which is
/// how a dimmed pane can still be the one you are moving.
@MainActor
final class ComposableTabsArrangeOverlayView: NSView {

    typealias Direction = ComposableTabsViewController.Direction

    var onAdd: (() -> Void)?
    var onRemove: (() -> Void)?
    var onMove: ((Direction) -> Void)?
    var onDone: (() -> Void)?

    /// Re-read on every `refreshAvailability()`; the tree changes under this
    /// view every time any pane moves.
    var canAdd: () -> Bool = { true }
    var canRemove: () -> Bool = { true }
    var availableDirections: () -> Set<Direction> = { [] }

    /// What this pane is, named above the toolbar. In arrange mode the content
    /// is dimmed to the point of being unreadable, which is exactly when the
    /// user needs to know which pane they are about to move.
    var paneName: String = "" {
        didSet { nameLabel.stringValue = paneName }
    }

    /// The button the add popover anchors to.
    var addButtonView: NSView { addButton }

    private let toolbar = NSView()
    private let nameLabel = ThemedLabel(string: "", role: .primaryText, textRole: .heading)
    private let addButton: NSButton
    private let removeButton: NSButton
    private let moveButton = NSPopUpButton(frame: .zero, pullsDown: true)

    /// The four direction items, built by the one thing that knows them. The
    /// pane's gear menu asks the same object for the same items.
    private let moveMenu = ComposableTabsMoveMenu()
    private let doneButton: NSButton

    override init(frame frameRect: NSRect) {
        addButton = Self.makeButton(title: "Add", symbolName: "plus")
        removeButton = Self.makeButton(title: "Remove", symbolName: "minus")
        doneButton = Self.makeButton(title: "Done", symbolName: "checkmark")
        super.init(frame: frameRect)
        wantsLayer = true
        accessibilityID("composable-tabs.arrange.scrim")

        addButton.target = self
        addButton.action = #selector(addTapped(_:))
        addButton.accessibilityID("composable-tabs.arrange.add")

        removeButton.target = self
        removeButton.action = #selector(removeTapped(_:))
        removeButton.accessibilityID("composable-tabs.arrange.remove")

        moveButton.bezelStyle = .rounded
        moveButton.addItem(withTitle: "Move")
        moveButton.menu?.autoenablesItems = false
        moveButton.accessibilityID("composable-tabs.arrange.move")
        moveMenu.availableDirections = { [weak self] in self?.availableDirections() ?? [] }
        moveMenu.onMove = { [weak self] direction in self?.onMove?(direction) }

        // Return, Enter and Escape already leave the mode, but none of them is
        // visible. A pane that shows every other thing arranging can do owes
        // the way out the same billing (`explicit-over-implicit`). No `\r` key
        // equivalent: every pane in the window carries one of these, and a
        // window with four default buttons has none.
        doneButton.target = self
        doneButton.action = #selector(doneTapped(_:))
        doneButton.accessibilityID("composable-tabs.arrange.done")

        buildToolbar()
        observeTheme { view, palette in view.applyPalette(palette) }
        refreshAvailability()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func makeButton(title: String, symbolName: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        return button
    }

    private func buildToolbar() {
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 8
        toolbar.layer?.borderWidth = 1
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [addButton, removeButton, moveButton, doneButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)

        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.accessibilityID("composable-tabs.arrange.pane-name")

        let column = NSStackView(views: [nameLabel, toolbar])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 8),
            toolbar.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),

            // Centred, and allowed to overhang a pane too narrow to hold it —
            // the alternative is forcing the split wider than the user sized it.
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            column.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -16)
        ])
    }

    private func applyPalette(_ palette: SemanticPalette) {
        // Dimming toward the window background rather than toward black keeps
        // a light theme light — the content reads as *behind* something, not
        // as switched off.
        layer?.backgroundColor = palette.nsColor(.windowBackground).withAlphaComponent(0.72).cgColor
        toolbar.layer?.backgroundColor = palette.nsColor(.elevatedSurface).cgColor
        toolbar.layer?.borderColor = palette.nsColor(.border).cgColor
    }

    /// Re-reads what this pane may do. Called whenever the tree changes, since
    /// the last remaining pane cannot be removed and a pane at the top of the
    /// window has no `Up`.
    func refreshAvailability() {
        addButton.isEnabled = canAdd()
        removeButton.isEnabled = canRemove()

        // A pull-down's first item is its own label, never a choice — so it
        // survives the rebuild and the four real items follow it.
        let title = moveButton.menu?.items.first
        moveButton.menu?.removeAllItems()
        if let title { moveButton.menu?.addItem(title) }

        let items = moveMenu.makeItems(accessibilityPrefix: "composable-tabs.arrange.move")
        for item in items { moveButton.menu?.addItem(item) }
        moveButton.isEnabled = items.contains { $0.isEnabled }
    }

    @objc private func addTapped(_ sender: Any?) { onAdd?() }
    @objc private func removeTapped(_ sender: Any?) { onRemove?() }
    @objc private func doneTapped(_ sender: Any?) { onDone?() }
}
