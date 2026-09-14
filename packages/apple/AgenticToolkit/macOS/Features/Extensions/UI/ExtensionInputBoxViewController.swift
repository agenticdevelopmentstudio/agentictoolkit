//
//  ExtensionInputBoxViewController.swift
//  AgenticToolkit
//

import AppKit
import AgenticDeveloperToolkitUI

/// The input box's one screen: an optional title, an optional prompt, a
/// single field, and a validation message.
///
/// AppKit rather than SwiftUI, on `ExtensionQuickPickViewController`'s
/// precedent — the two share a panel (part 4) and a keyboard controller.
@MainActor
final class ExtensionInputBoxViewController: NSViewController {

    // MARK: - Callbacks

    /// Return, when `model.canAccept`. Carries the field's current value —
    /// an empty string is a value, and Return accepts it.
    var onAccept: (String) -> Void = { _ in }

    /// Escape.
    var onCancel: () -> Void = {}

    /// The field's text changed. The presenter turns this into a `validate`
    /// round trip and calls `showValidation` back.
    var onValueChanged: (String) -> Void = { _ in }

    // MARK: - State

    private let model: ExtensionInputBoxModel

    // MARK: - Views

    private var titleLabel: ThemedLabel?
    private var promptLabel: ThemedLabel?
    private let field: NSTextField
    private let validationLabel = ThemedLabel(role: .danger, textRole: .caption)

    private let keyboard = PickerKeyboardController()

    // MARK: - Lifecycle

    init(model: ExtensionInputBoxModel) {
        self.model = model
        // Chosen once here rather than in `loadView`: a field that changes
        // class after it has focus loses the caret and the typed text, and
        // `isPassword` cannot change during one request, so there is exactly
        // one moment this decision needs to be made.
        self.field = model.request.isPassword ? NSSecureTextField() : NSTextField()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true

        var subviews: [NSView] = []
        var title: ThemedLabel?
        if let requestTitle = model.request.title, !requestTitle.isEmpty {
            let label = ThemedLabel(string: requestTitle, role: .primaryText, textRole: .heading)
            title = label
            subviews.append(label)
        }
        titleLabel = title

        var prompt: ThemedLabel?
        if let requestPrompt = model.request.prompt, !requestPrompt.isEmpty {
            let label = ThemedLabel(string: requestPrompt, role: .secondaryText, textRole: .caption)
            prompt = label
            subviews.append(label)
        }
        promptLabel = prompt

        field.placeholderString = model.request.placeHolder ?? ""
        field.delegate = self
        field.accessibilityID("extension-input-box.field")
        subviews.append(field)

        validationLabel.isHidden = true
        validationLabel.lineBreakMode = .byWordWrapping
        validationLabel.maximumNumberOfLines = 0
        subviews.append(validationLabel)

        for subview in subviews {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }

        var constraints: [NSLayoutConstraint] = []
        var previous: NSView = root
        var previousIsRoot = true
        for subview in [title, prompt].compactMap({ $0 }) as [NSView] {
            constraints.append(contentsOf: [
                subview.topAnchor.constraint(
                    equalTo: previousIsRoot ? previous.topAnchor : previous.bottomAnchor, constant: 12),
                subview.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
                subview.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12)
            ])
            previous = subview
            previousIsRoot = false
        }

        constraints.append(contentsOf: [
            field.topAnchor.constraint(
                equalTo: previousIsRoot ? previous.topAnchor : previous.bottomAnchor, constant: 12),
            field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            validationLabel.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            validationLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            validationLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            validationLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
        NSLayoutConstraint.activate(constraints)
        self.view = root

        // Set from the assembled Auto Layout height so part 4's window
        // controller can size the panel from `preferredContentSize` alone.
        root.layoutSubtreeIfNeeded()
        let width: CGFloat = 480
        let fittingHeight = root.fittingSize.height
        preferredContentSize = NSSize(width: width, height: max(fittingHeight, 72))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        keyboard.onChoose = { [weak self] in self?.choose() }
        keyboard.onCancel = { [weak self] in self?.onCancel() }
        field.stringValue = model.value
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        keyboard.startEscapeMonitor(for: view.window)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        keyboard.stopEscapeMonitor()
    }

    // MARK: - Public API

    /// Give the field the keyboard, then apply the model's initial
    /// selection. **After** `makeFirstResponder` — a field with no field
    /// editor has no selection to set.
    func focusField() {
        view.window?.makeFirstResponder(field)
        // `initialSelectionUTF16Range()`, not a raw `NSRange` built from
        // `initialSelection()`'s Character offsets directly — `NSRange` is
        // UTF-16, and a Character offset is not (F7).
        field.currentEditor()?.selectedRange = model.initialSelectionUTF16Range()
    }

    /// Record `validation` on the model and paint the label: hidden for nil,
    /// otherwise the message in the role the severity picks. Theme roles
    /// throughout — a hard-coded `NSColor.systemRed` would be the one colour
    /// in the panel a theme could not reach.
    func showValidation(_ validation: ExtensionInputValidation?) {
        model.recordValidation(validation)
        guard let validation else {
            validationLabel.isHidden = true
            return
        }
        validationLabel.isHidden = false
        validationLabel.stringValue = validation.message
        switch validation.severity {
        case .error: validationLabel.role = .danger
        case .warning: validationLabel.role = .warning
        case .information: validationLabel.role = .secondaryText
        }
    }

    // MARK: - Actions

    /// Return, only when `model.canAccept` — Return under an `.error` does
    /// nothing and the message stays on screen (the contract quoted on
    /// `ExtensionInputBoxModel.canAccept`).
    private func choose() {
        guard model.canAccept else { return }
        onAccept(model.value)
    }
}

// MARK: - Field

extension ExtensionInputBoxViewController: NSTextFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        let value = field.stringValue
        model.value = value
        onValueChanged(value)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        keyboard.handle(commandSelector)
    }
}
