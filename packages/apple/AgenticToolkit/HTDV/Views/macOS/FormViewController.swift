#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AgenticDeveloperToolkit
import AgenticDeveloperToolkitUI
import AppKit

/// Renders a `FormState` as a scrolling AppKit form with a save/revert/delete footer.
public final class FormViewController: NSViewController, HTDVDetailHosting, NSTextFieldDelegate, NSTextViewDelegate {
    public let state: FormState
    public var onSaved: () -> Void = {}
    public var onDeleted: () -> Void = {}
    public var hasUnsavedChanges: Bool { state.isDirty }

    /// Set by the HTDV host the first time it chains its level-reload onto `onSaved`/`onDeleted`.
    ///
    /// The flag lives on the form rather than in a host-side `Set<ObjectIdentifier>`: `renderDetail()`
    /// releases the outgoing detail BEFORE building the incoming one, so a freed form's address can be
    /// handed straight back to its replacement. The set then reported the brand-new form as already
    /// attached, the chaining was skipped, and the rail silently stopped reloading after save and
    /// delete. An identity that cannot be recycled — the object's own storage — cannot collide.
    var hasHostLevelReloadAttached = false

    let saveButton = ThemedActionButton(title: "Save", style: .primary)
    let revertButton = ThemedActionButton(title: "Revert")
    let deleteButton = ThemedActionButton(title: "Delete", style: .destructive)
    let blockedLabel = ThemedLabel(role: .secondaryText, textRole: .caption)
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    /// Errors from `actions.delete` / `actions.extra`. Separate from `errorLabel` because that one is
    /// owned by `syncFromState()`, which rewrites it on every state change — so an action failure
    /// written there was erased by the user's very next keystroke (I5). Nothing in the state → UI
    /// path touches this label; only `performDelete()` / `performExtra(id:)` write and clear it.
    let actionErrorLabel = NSTextField(wrappingLabelWithString: "")

    /// Overridable so tests can drive the confirm/cancel branches; a modal alert would hang the suite.
    var confirmDiscardHandler: () async -> Bool = {
        let alert = NSAlert()
        alert.messageText = "Discard changes?"
        alert.informativeText = "You have unsaved changes. Discarding them cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Keep Editing")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Overridable so tests can drive the confirm/cancel branches; a modal alert would hang the suite.
    var confirmDeleteHandler: (FormDeleteAction) async -> Bool = { delete in
        let alert = NSAlert()
        alert.messageText = delete.title
        alert.informativeText = delete.confirmationText ?? "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: delete.title)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private let markdownEditing: any MarkdownEditing
    private var controls: [String: NSView] = [:]
    private var fieldErrorLabels: [String: NSTextField] = [:]
    private var textViewKeys: [ObjectIdentifier: String] = [:]
    private var extraButtons: [String: NSButton] = [:]
    /// The three pieces of a `.date` row, keyed by field key. A date row is a stack rather than a bare
    /// picker because `NSDatePicker` cannot represent "no date" — see `applyDateRow(key:value:)`.
    private var datePickers: [String: NSDatePicker] = [:]
    private var dateSetButtons: [String: NSButton] = [:]
    private var dateClearButtons: [String: NSButton] = [:]
    /// The control the in-flight edit came from. `syncFromState()` skips it, because reformatting a
    /// field mid-keystroke destroys what the user typed: "1." round-trips to "1", "-" to "", and
    /// "alpha," to "alpha". Compare-before-assign does not help — those values genuinely differ from
    /// their formatted form. Identity is the only thing that distinguishes "the user typed this" from
    /// "the model changed underneath us".
    private weak var controlBeingEdited: NSControl?
    private var isSyncingFromState = false
    /// Guards `performDelete()` against a second tap while the first is still awaiting confirmation or
    /// the delete itself; `delete.perform()` is destructive and not idempotent.
    private var isDeleting = false
    /// Guards `performExtra(id:)` against a second tap on the same action while the first is in flight.
    private var runningExtraActionIDs: Set<String> = []
    private lazy var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    public init(state: FormState, markdownEditing: any MarkdownEditing) {
        self.state = state
        self.markdownEditing = markdownEditing
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func control(for key: String) -> NSView? { controls[key] }
    func errorLabel(for key: String) -> String? {
        guard let label = fieldErrorLabels[key], !label.isHidden else { return nil }
        return label.stringValue
    }
    /// Unlike `errorLabel(for:)`, returns the label view itself regardless of visibility — for tests
    /// that need to check the accessibility identifier rather than the currently-shown message.
    func errorLabelView(for key: String) -> NSTextField? { fieldErrorLabels[key] }
    func extraButton(for id: String) -> NSButton? { extraButtons[id] }
    /// `controls[key]` holds the whole date ROW (see `buildDateRow(for:)`), so tests and the sync path
    /// reach the picker itself through here.
    func datePicker(for key: String) -> NSDatePicker? { datePickers[key] }
    func dateSetButton(for key: String) -> NSButton? { dateSetButtons[key] }
    func dateClearButton(for key: String) -> NSButton? { dateClearButtons[key] }

    // MARK: Build

    override public func loadView() {
        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 12
        form.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        form.translatesAutoresizingMaskIntoConstraints = false
        for section in state.spec.sections {
            if let title = section.title {
                // Was `boldSystemFont(ofSize: systemFontSize + 1)` — arithmetic
                // on the system font, which no theme size or family reaches.
                // `heading` is the role that means "section header".
                form.addArrangedSubview(ThemedLabel(string: title, textRole: .heading))
            }
            for field in section.fields {
                let row = buildRow(for: field)
                form.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: form.widthAnchor, constant: -40).isActive = true
            }
        }
        let footer = buildFooter()
        form.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: form.widthAnchor, constant: -40).isActive = true

        // The form's root scroll stays transparent on purpose: a form is shown
        // inside a detail pane or a sheet, and each of those owns a different
        // plane (`windowBackground` vs `surface`). Drawing its own would put a
        // seam down the one it sits in.
        let scroll = ThemedScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(form)
        scroll.documentView = document
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            form.topAnchor.constraint(equalTo: document.topAnchor),
            form.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])
        view = scroll
        state.onChange = { [weak self] _ in self?.syncFromState() }
        syncFromState()
    }

    private func buildRow(for field: FormField) -> NSView {
        let label = ThemedLabel(string: field.label, role: .secondaryText, textRole: .caption, weight: .medium)
        let control = buildControl(for: field)
        controls[field.key] = control
        // Wrapping, so it stays an `NSTextField` — the one thing `ThemedLabel`
        // is not — and takes its colour and font from the palette directly.
        let error = NSTextField(wrappingLabelWithString: "")
        error.observeTheme { error, palette in
            error.textColor = palette.dangerColor
            error.font = palette.font(.caption)
        }
        error.isHidden = true
        error.setAccessibilityIdentifier("htdv.form.error.\(field.key)")
        fieldErrorLabels[field.key] = error
        let stack = NSStackView(views: [label, control, error])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func buildControl(for field: FormField) -> NSView {
        switch field {
        case .text(let textField):
            let text: NSTextField = textField.isSecure ? NSSecureTextField() : NSTextField()
            text.placeholderString = textField.placeholder
            text.identifier = NSUserInterfaceItemIdentifier(textField.key)
            text.target = self
            text.action = #selector(textFieldChanged(_:))
            text.delegate = self
            text.setAccessibilityIdentifier("htdv.form.field.\(textField.key)")
            // Not a `ThemedTextField`: the form builds the field by kind (a
            // secure one here) and wires target, action and delegate onto it,
            // so the paint job arrives as an extension instead.
            text.observeTheme { text, palette in text.applyEditableFieldTheme(palette) }
            return text
        case .number(let numberField):
            let text = NSTextField()
            text.identifier = NSUserInterfaceItemIdentifier(numberField.key)
            text.target = self
            text.action = #selector(textFieldChanged(_:))
            text.delegate = self
            text.setAccessibilityIdentifier("htdv.form.field.\(numberField.key)")
            text.observeTheme { text, palette in text.applyEditableFieldTheme(palette) }
            return text
        case .stringSet(let stringSetField):
            let text = NSTextField()
            text.placeholderString = stringSetField.placeholder ?? "Comma-separated"
            text.identifier = NSUserInterfaceItemIdentifier(stringSetField.key)
            text.target = self
            text.action = #selector(textFieldChanged(_:))
            text.delegate = self
            text.setAccessibilityIdentifier("htdv.form.field.\(stringSetField.key)")
            text.observeTheme { text, palette in text.applyEditableFieldTheme(palette) }
            return text
        case .textArea(let textAreaField):
            return buildTextView(key: textAreaField.key, minLines: textAreaField.minLines, monospaced: false)
        case .json(let jsonField):
            return buildTextView(key: jsonField.key, minLines: 6, monospaced: true)
        case .toggle(let toggleField):
            let toggle = NSSwitch()
            toggle.identifier = NSUserInterfaceItemIdentifier(toggleField.key)
            toggle.target = self
            toggle.action = #selector(toggleChanged(_:))
            toggle.setAccessibilityIdentifier("htdv.form.field.\(toggleField.key)")
            return toggle
        case .select(let selectField):
            let popup = NSPopUpButton()
            popup.identifier = NSUserInterfaceItemIdentifier(selectField.key)
            popup.setAccessibilityIdentifier("htdv.form.field.\(selectField.key)")
            popup.addItem(withTitle: "—")
            popup.lastItem?.representedObject = ""
            for option in selectField.options {
                popup.addItem(withTitle: option.title)
                popup.lastItem?.representedObject = option.value
            }
            popup.target = self
            popup.action = #selector(popupChanged(_:))
            return popup
        case .date(let dateField):
            return buildDateRow(for: dateField)
        case .readOnly(let readOnlyField):
            let text = NSTextField(wrappingLabelWithString: "")
            text.isSelectable = true
            text.maximumNumberOfLines = 0
            text.lineBreakMode = .byWordWrapping
            text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            text.identifier = NSUserInterfaceItemIdentifier(readOnlyField.key)
            text.setAccessibilityIdentifier("htdv.form.field.\(readOnlyField.key)")
            // `code` *is* the theme's monospaced role, so a monospaced
            // read-only value now follows the theme's code font rather than
            // the system's.
            let textRole: TextRole = readOnlyField.isMonospaced ? .code : .body
            text.observeTheme { text, palette in
                text.textColor = palette.primaryTextColor
                text.font = palette.font(textRole)
            }
            return text
        case .markdown(let markdownField):
            let key = markdownField.key
            let initialText = state.value(for: key).stringValue ?? ""
            let editor = markdownEditing.makeEditor(initialText: initialText) { [weak self] in
                self?.markdownChanged($0, key: key)
            }
            addChild(editor)
            editor.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
            // `editor.view` is an opaque container from whatever `MarkdownEditing` conformer the host
            // supplies (`HubModules.markdownEditing`, typically) — this framework has no visibility into
            // its internal accessibility tree, so the container itself is made the addressable element
            // for the field, per the "container needs a role too" rule.
            editor.view.setAccessibilityIdentifier("htdv.form.field.\(key)")
            editor.view.setAccessibilityElement(true)
            editor.view.setAccessibilityRole(.group)
            return editor.view
        }
    }

    /// A `.date` row: picker, "Set date", "Clear". `NSDatePicker` has no empty state — it renders
    /// today for a null value — so the row shows the picker only when the model actually holds a date
    /// and offers "Set date" otherwise. `applyDateRow(key:value:)` owns which of the three is visible.
    private func buildDateRow(for field: FormDateField) -> NSView {
        let picker = NSDatePicker()
        picker.identifier = NSUserInterfaceItemIdentifier(field.key)
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay]
        picker.target = self
        picker.action = #selector(dateChanged(_:))
        picker.setAccessibilityIdentifier("htdv.form.field.\(field.key)")
        datePickers[field.key] = picker

        // Not in the brief's literal list (only the row's overall field identifier is named there),
        // but these are the two real controls that stand in for the picker when the model holds no
        // date — see `applyDateRow`. Namespaced under the field's own identifier so both stay
        // discoverable from it.
        let setButton = ThemedActionButton(title: "Set date", target: self, action: #selector(setDateTapped(_:)))
        setButton.identifier = NSUserInterfaceItemIdentifier(field.key)
        setButton.setAccessibilityIdentifier("htdv.form.field.\(field.key).set")
        dateSetButtons[field.key] = setButton

        let clearButton = ThemedActionButton(title: "Clear", target: self, action: #selector(clearDateTapped(_:)))
        clearButton.identifier = NSUserInterfaceItemIdentifier(field.key)
        clearButton.setAccessibilityIdentifier("htdv.form.field.\(field.key).clear")
        dateClearButtons[field.key] = clearButton

        let row = NSStackView(views: [picker, setButton, clearButton, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func buildTextView(key: String, minLines: Int, monospaced: Bool) -> NSView {
        let textView = NSTextView()
        textView.isRichText = false
        let textRole: TextRole = monospaced ? .code : .body
        textView.observeTheme { textView, palette in
            textView.backgroundColor = palette.controlBackgroundColor
            textView.textColor = palette.primaryTextColor
            textView.insertionPointColor = palette.cursorColor
            textView.font = palette.font(textRole)
        }
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.delegate = self
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityIdentifier("htdv.form.field.\(key)")
        textViewKeys[ObjectIdentifier(textView)] = key
        // Bezel border and all: a text view is a *well*, so unlike the form's
        // own transparent scroll this one draws its own themed plane.
        let scroll = ThemedScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.identifier = NSUserInterfaceItemIdentifier(key)
        scroll.heightAnchor.constraint(equalToConstant: CGFloat(minLines) * 18 + 8).isActive = true
        return scroll
    }

    private func buildFooter() -> NSView {
        // Both error labels wrap, so neither can be a `ThemedLabel`.
        for label in [errorLabel, actionErrorLabel] {
            label.observeTheme { label, palette in
                label.textColor = palette.dangerColor
                label.font = palette.font(.caption)
            }
        }
        actionErrorLabel.isHidden = true
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.setAccessibilityIdentifier("htdv.form.save")
        // Not named by the brief (which only calls out save/cancel), but revert and delete are real
        // footer controls too, so they get the same "<feature>.<element>" shape rather than being left
        // unaddressable.
        revertButton.target = self
        revertButton.action = #selector(revertTapped)
        revertButton.setAccessibilityIdentifier("htdv.form.revert")
        // `hasDestructiveAction` stays for assistive technologies; the red is
        // now the palette's `danger`, not the system's.
        deleteButton.hasDestructiveAction = true
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.isHidden = state.spec.actions.delete == nil
        deleteButton.setAccessibilityIdentifier("htdv.form.delete")
        if let delete = state.spec.actions.delete { deleteButton.title = delete.title }
        if let save = state.spec.actions.save { saveButton.title = save.title }
        saveButton.isHidden = state.spec.actions.save == nil
        revertButton.isHidden = state.spec.actions.save == nil

        var views: [NSView] = [deleteButton]
        for action in state.spec.actions.extra {
            let button = ThemedActionButton(
                title: action.title,
                style: action.isDestructive ? .destructive : .secondary,
                target: self,
                action: #selector(extraTapped(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(action.id)
            button.hasDestructiveAction = action.isDestructive
            button.setAccessibilityIdentifier("htdv.form.action.\(action.id)")
            extraButtons[action.id] = button
            views.append(button)
        }
        let errors = NSStackView(views: [errorLabel, actionErrorLabel])
        errors.orientation = .vertical
        errors.alignment = .leading
        errors.spacing = 2
        views.append(contentsOf: [NSView(), blockedLabel, errors, revertButton, saveButton])
        let footer = NSStackView(views: views)
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        return footer
    }

    // MARK: State → UI

    private func syncFromState() {
        isSyncingFromState = true
        defer { isSyncingFromState = false }
        for field in state.spec.fields {
            guard let control = controls[field.key] else { continue }
            // Skip only the CONTROL the edit came from; its error label below still updates, so a
            // value the user is typing can still show its validation error while it is being typed.
            if control !== controlBeingEdited {
                syncControl(control, for: field)
            }
            let label = fieldErrorLabels[field.key]
            label?.stringValue = state.errors[field.key] ?? ""
            label?.isHidden = state.errors[field.key] == nil
        }
        saveButton.isEnabled = state.canSave
        revertButton.isEnabled = state.isDirty && !state.isSaving
        blockedLabel.stringValue = state.blockedReason ?? ""
        blockedLabel.isHidden = state.blockedReason == nil
        errorLabel.stringValue = state.saveError ?? ""
        errorLabel.isHidden = state.saveError == nil
    }

    private func syncControl(_ control: NSView, for field: FormField) {
        let value = state.value(for: field.key)
        switch (field, control) {
        case (.stringSet, let text as NSTextField):
            text.stringValue = (value.stringSetValue ?? []).joined(separator: ", ")
        case (.number, let text as NSTextField):
            text.stringValue = value.numberValue.map {
                numberFormatter.string(from: NSNumber(value: $0)) ?? ""
            } ?? ""
        case (.text, let text as NSTextField), (.readOnly, let text as NSTextField):
            if text.stringValue != value.stringValue ?? "" { text.stringValue = value.stringValue ?? "" }
        case (.toggle, let toggle as NSSwitch):
            toggle.state = (value.boolValue ?? false) ? .on : .off
        case (.select, let popup as NSPopUpButton):
            let selected = value.stringValue ?? ""
            if let index = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == selected }) {
                popup.selectItem(at: index)
            }
        case (.date(let dateField), _):
            applyDateRow(key: dateField.key, value: value, isRequired: dateField.isRequired)
        case (.textArea, let scroll as NSScrollView), (.json, let scroll as NSScrollView):
            if let textView = scroll.documentView as? NSTextView, textView.string != value.stringValue ?? "" {
                textView.string = value.stringValue ?? ""
            }
        case (.markdown, _):
            break
        default:
            break
        }
    }

    /// Shows exactly one of "picker (+ Clear)" and "Set date", so the row never claims a date the model
    /// does not hold. A required field gets no Clear button: emptying it could only produce an error.
    private func applyDateRow(key: String, value: FormValue, isRequired: Bool) {
        let date = value.dateValue
        if let date { datePickers[key]?.dateValue = date }
        datePickers[key]?.isHidden = date == nil
        dateSetButtons[key]?.isHidden = date != nil
        dateClearButtons[key]?.isHidden = date == nil || isRequired
    }

    // MARK: UI → State

    @objc func textFieldChanged(_ sender: NSTextField) {
        // Defence against re-entry through syncFromState, not a workaround for a specific control.
        guard !isSyncingFromState, let key = sender.identifier?.rawValue else { return }
        guard let field = state.spec.fields.first(where: { $0.key == key }) else { return }
        // Deliberately identity, not first-responder state: `state.set` re-enters `syncFromState()`
        // synchronously, and the tests (and `controlTextDidChange`) reach here with no window and no
        // field editor, so a responder check would not hold.
        controlBeingEdited = sender
        defer { controlBeingEdited = nil }
        switch field {
        case .number:
            let trimmed = sender.stringValue.trimmingCharacters(in: .whitespaces)
            state.set(trimmed.isEmpty ? .null : (Double(trimmed).map { .number($0) } ?? .string(trimmed)), for: key)
        case .stringSet:
            let parts = sender.stringValue.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            state.set(.stringSet(parts), for: key)
        default:
            state.set(.string(sender.stringValue), for: key)
        }
    }

    public func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        textFieldChanged(field)
    }

    public func textDidChange(_ notification: Notification) {
        // Defence against re-entry through syncFromState, not a workaround for a specific control.
        guard !isSyncingFromState, let textView = notification.object as? NSTextView,
              let key = textViewKeys[ObjectIdentifier(textView)] else { return }
        state.set(.string(textView.string), for: key)
    }

    @objc private func toggleChanged(_ sender: NSSwitch) {
        // Defence against re-entry through syncFromState, not a workaround for a specific control.
        guard !isSyncingFromState, let key = sender.identifier?.rawValue else { return }
        state.set(.bool(sender.state == .on), for: key)
    }

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        // Defence against re-entry through syncFromState, not a workaround for a specific control.
        guard !isSyncingFromState, let key = sender.identifier?.rawValue else { return }
        let value = (sender.selectedItem?.representedObject as? String) ?? ""
        state.set(value.isEmpty ? .null : .string(value), for: key)
    }

    @objc private func dateChanged(_ sender: NSDatePicker) {
        // Defence against re-entry through syncFromState, not a workaround for a specific control.
        guard !isSyncingFromState, let key = sender.identifier?.rawValue else { return }
        state.set(.date(sender.dateValue), for: key)
    }

    /// Commits today's date immediately rather than just revealing the picker, so the value the row
    /// starts displaying is the value the model holds — the bug this replaced was exactly that gap.
    @objc private func setDateTapped(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        state.set(.date(Date()), for: key)
    }

    @objc private func clearDateTapped(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        state.set(.null, for: key)
    }

    private func markdownChanged(_ text: String, key: String) {
        state.set(.string(text), for: key)
    }

    // MARK: Footer actions

    @objc private func saveTapped() {
        Task { await performSave() }
    }

    func performSave() async {
        if await state.save() { onSaved() }
    }

    @objc private func revertTapped() {
        state.revert()
        for field in state.spec.fields {
            guard case .markdown = field,
                  let editor = children.first(where: { $0.view === controls[field.key] }) else { continue }
            (editor as? MarkdownTextReplacing)?.replaceText(with: state.value(for: field.key).stringValue ?? "")
        }
    }

    @objc private func deleteTapped() {
        Task { await performDelete() }
    }

    /// Runs the confirm → perform → `onDeleted` flow. A separate `async` entry point (mirroring
    /// `performSave()`) so tests can await the whole flow instead of racing an unawaited `Task`.
    func performDelete() async {
        guard let delete = state.spec.actions.delete, !isDeleting else { return }
        clearActionError()
        isDeleting = true
        deleteButton.isEnabled = false
        defer {
            isDeleting = false
            deleteButton.isEnabled = true
        }
        guard await confirmDeleteHandler(delete) else { return }
        do {
            try await delete.perform()
            onDeleted()
        } catch {
            showActionError(error)
        }
    }

    @objc private func extraTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        Task { await performExtra(id: id) }
    }

    /// Runs one `actions.extra` entry by id. A separate `async` entry point (mirroring `performSave()`)
    /// so tests can await the whole flow instead of racing an unawaited `Task`.
    func performExtra(id: String) async {
        guard let action = state.spec.actions.extra.first(where: { $0.id == id }),
              !runningExtraActionIDs.contains(id) else { return }
        clearActionError()
        runningExtraActionIDs.insert(id)
        extraButtons[id]?.isEnabled = false
        defer {
            runningExtraActionIDs.remove(id)
            extraButtons[id]?.isEnabled = true
        }
        do {
            try await action.perform(state.values)
        } catch {
            showActionError(error)
        }
    }

    private func clearActionError() {
        actionErrorLabel.stringValue = ""
        actionErrorLabel.isHidden = true
    }

    private func showActionError(_ error: Error) {
        actionErrorLabel.stringValue = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        actionErrorLabel.isHidden = false
    }

    // MARK: HTDVDetailHosting

    public func confirmDiscard() async -> Bool {
        await confirmDiscardHandler()
    }
}
#endif
