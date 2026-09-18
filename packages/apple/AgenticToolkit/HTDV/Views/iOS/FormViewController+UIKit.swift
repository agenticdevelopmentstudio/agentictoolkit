#if canImport(UIKit)
import AgenticDeveloperToolkit
import AgenticDeveloperToolkitUI
import UIKit

/// Renders a `FormState` as a scrolling UIKit form with a save/revert/delete footer.
public final class FormViewController: UIViewController, HTDVDetailHosting, UITextViewDelegate {
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

    let saveButton = UIButton(type: .system)
    let revertButton = UIButton(type: .system)
    let deleteButton = UIButton(type: .system)
    let blockedLabel = UILabel()
    let errorLabel = UILabel()
    /// Errors from `actions.delete` / `actions.extra`. Separate from `errorLabel` because that one is
    /// owned by `syncFromState()`, which rewrites it on every state change, so an action failure
    /// written there was erased by the user's very next keystroke (I5). Nothing in the state-to-UI
    /// path touches this label; only `performDelete()` / `performExtra(id:)` write and clear it.
    let actionErrorLabel = UILabel()

    /// Overridable so tests can drive the confirm/cancel branches; a modal alert would hang the suite.
    /// The real default needs `self` to present, so it starts as a placeholder here and `init` replaces
    /// it with one that captures `self` weakly, once `self` is fully initialized.
    var confirmDiscardHandler: () async -> Bool = { false }
    /// Overridable so tests can drive the confirm/cancel branches; a modal alert would hang the suite.
    /// The real default needs `self` to present, so it starts as a placeholder here and `init` replaces
    /// it with one that captures `self` weakly, once `self` is fully initialized.
    var confirmDeleteHandler: (FormDeleteAction) async -> Bool = { _ in false }

    private let markdownEditing: any MarkdownEditing
    private var controls: [String: UIView] = [:]
    private var fieldErrorLabels: [String: UILabel] = [:]
    private var textViewKeys: [ObjectIdentifier: String] = [:]
    private var extraButtons: [String: UIButton] = [:]
    /// The three pieces of a `.date` row, keyed by field key. A date row is a stack rather than a bare
    /// picker because `UIDatePicker` cannot represent "no date". See `applyDateRow(key:value:)`.
    private var datePickers: [String: UIDatePicker] = [:]
    private var dateSetButtons: [String: UIButton] = [:]
    private var dateClearButtons: [String: UIButton] = [:]
    /// Every `UITextView` whose border is drawn with a `CGColor`. A `CGColor` is a colour already
    /// resolved against one trait collection and frozen there, so the border has to be re-resolved by
    /// hand on every appearance change. See the `registerForTraitChanges` call in `viewDidLoad`.
    private var borderedTextViews: [UITextView] = []
    /// The control the in-flight edit came from. `syncFromState()` skips it, because reformatting a
    /// field mid-keystroke destroys what the user typed: "1." round-trips to "1", "-" to "", and
    /// "alpha," to "alpha". Compare-before-assign does not help; those values genuinely differ from
    /// their formatted form. Identity is the only thing that distinguishes "the user typed this" from
    /// "the model changed underneath us".
    private weak var controlBeingEdited: UIControl?
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
        installDefaultConfirmHandlers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func control(for key: String) -> UIView? { controls[key] }
    /// `controls[key]` holds the whole date ROW (see `buildDateRow(for:)`), so tests and the sync path
    /// reach the picker itself through here.
    func datePicker(for key: String) -> UIDatePicker? { datePickers[key] }
    func dateSetButton(for key: String) -> UIButton? { dateSetButtons[key] }
    func dateClearButton(for key: String) -> UIButton? { dateClearButtons[key] }
    func errorLabel(for key: String) -> String? {
        guard let label = fieldErrorLabels[key], !label.isHidden else { return nil }
        return label.text
    }

    // MARK: Build

    override public func viewDidLoad() {
        super.viewDidLoad()
        // A form is presented inside a detail pane or pushed onto a navigation
        // stack, and `surface` is the plane the palette gives to a thing on top
        // of the window.
        view.observeTheme { view, palette in view.backgroundColor = palette.surfaceColor }
        let form = UIStackView()
        form.axis = .vertical
        form.spacing = 12
        form.isLayoutMarginsRelativeArrangement = true
        form.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        form.translatesAutoresizingMaskIntoConstraints = false
        for section in state.spec.sections {
            if let title = section.title {
                // `preferredFont(forTextStyle:)` is the system's type ramp, not
                // the theme's — `heading` is the role that means this.
                form.addArrangedSubview(ThemedLabel(string: title, textRole: .heading))
            }
            for field in section.fields {
                form.addArrangedSubview(buildRow(for: field))
                // A markdown field's editor is added as a child (`addChild`) inside `buildControl`, but
                // UIKit's containment contract wants `didMove(toParent:)` sent only after the child's view
                // is actually in this view controller's view hierarchy — which is exactly now, once the
                // row containing it has been inserted into the form stack.
                guard case .markdown = field, let control = controls[field.key],
                      let editor = children.first(where: { $0.view === control }) else { continue }
                editor.didMove(toParent: self)
            }
        }
        form.addArrangedSubview(buildFooter())

        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(form)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            form.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            form.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            form.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            form.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        let borderTraits: [any UITraitDefinition.Type] = [
            UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self
        ]
        registerForTraitChanges(borderTraits) { (self: Self, _) in self.applyTextViewBorderColors() }
        applyTextViewBorderColors()
        state.onChange = { [weak self] _ in self?.syncFromState() }
        syncFromState()
    }

    /// A palette colour can be dynamic; `.cgColor` is not. Converting once at build time froze the
    /// border at whatever the interface style happened to be then, leaving a light-mode hairline
    /// drawn over a dark-mode form (M4). The trait registration in `viewDidLoad` is what re-runs
    /// this; a theme *change* re-runs it through each text view's own theme observer.
    private func applyTextViewBorderColors() {
        let palette = view.resolvedThemeScope.palette
        for textView in borderedTextViews {
            textView.layer.borderColor = palette.borderColor.resolvedColor(with: traitCollection).cgColor
        }
    }

    /// Installs the real alert-backed confirm handlers. Called from `init` (after `super.init`, so `self`
    /// is fully initialized) rather than from a property initializer, so the default closures can capture
    /// `self` weakly instead of not at all — presenting a `UIAlertController` requires a view controller
    /// to present from. Each closure guards on the view actually being in a window before presenting:
    /// `present(_:animated:)` on a view controller that isn't on screen would never resolve the
    /// continuation, hanging the caller instead of failing fast the way the placeholder used to.
    private func installDefaultConfirmHandlers() {
        confirmDiscardHandler = { [weak self] in
            guard let self, self.viewIfLoaded?.window != nil else { return false }
            return await withCheckedContinuation { continuation in
                let alert = UIAlertController(
                    title: "Discard changes?", message: "You have unsaved changes.", preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Keep Editing", style: .cancel) { _ in
                    continuation.resume(returning: false)
                })
                alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { _ in
                    continuation.resume(returning: true)
                })
                self.present(alert, animated: true)
            }
        }
        confirmDeleteHandler = { [weak self] delete in
            guard let self, self.viewIfLoaded?.window != nil else { return false }
            return await withCheckedContinuation { continuation in
                let alert = UIAlertController(
                    title: delete.title,
                    message: delete.confirmationText ?? "This cannot be undone.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    continuation.resume(returning: false)
                })
                alert.addAction(UIAlertAction(title: delete.title, style: .destructive) { _ in
                    continuation.resume(returning: true)
                })
                self.present(alert, animated: true)
            }
        }
    }

    private func buildRow(for field: FormField) -> UIView {
        let label = ThemedLabel(string: field.label, role: .secondaryText, textRole: .caption)
        let control = buildControl(for: field)
        controls[field.key] = control
        let error = UILabel()
        error.observeTheme { error, palette in
            error.textColor = palette.dangerColor
            error.font = palette.font(.caption)
        }
        error.numberOfLines = 0
        error.isHidden = true
        fieldErrorLabels[field.key] = error
        let stack = UIStackView(arrangedSubviews: [label, control, error])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }

    private func makeTextField(key: String, placeholder: String?, secure: Bool = false) -> UITextField {
        let text = ThemedTextField()
        text.borderStyle = .roundedRect
        text.placeholder = placeholder
        text.isSecureTextEntry = secure
        text.autocorrectionType = .no
        text.autocapitalizationType = .none
        text.accessibilityIdentifier = key
        // `action.sender` rather than capturing `text`: the control owns the `UIAction`, which owns
        // this closure, so capturing the control here would close a retain cycle that outlives the
        // form (I1). UIKit hands the control back through `sender` for exactly this reason.
        text.addAction(UIAction { [weak self] action in
            guard let field = action.sender as? UITextField else { return }
            self?.textFieldChanged(field)
        }, for: .editingChanged)
        return text
    }

    private func buildControl(for field: FormField) -> UIView {
        switch field {
        case .text(let textField):
            return makeTextField(key: textField.key, placeholder: textField.placeholder, secure: textField.isSecure)
        case .number(let numberField):
            let text = makeTextField(key: numberField.key, placeholder: nil)
            text.keyboardType = numberField.isInteger ? .numberPad : .decimalPad
            return text
        case .stringSet(let stringSetField):
            return makeTextField(key: stringSetField.key, placeholder: stringSetField.placeholder ?? "Comma-separated")
        case .textArea(let textAreaField):
            return buildTextView(key: textAreaField.key, minLines: textAreaField.minLines, monospaced: false)
        case .json(let jsonField):
            return buildTextView(key: jsonField.key, minLines: 6, monospaced: true)
        case .toggle(let toggleField):
            let toggle = UISwitch()
            toggle.accessibilityIdentifier = toggleField.key
            // `action.sender` rather than capturing `toggle`, for the retain-cycle reason in
            // `makeTextField(key:placeholder:secure:)`.
            toggle.addAction(UIAction { [weak self] action in
                guard let self, !self.isSyncingFromState else { return }
                // Defence against re-entry through syncFromState, not a workaround for a specific control.
                guard let toggle = action.sender as? UISwitch else { return }
                self.state.set(.bool(toggle.isOn), for: toggleField.key)
            }, for: .valueChanged)
            let wrapper = UIStackView(arrangedSubviews: [toggle, UIView()])
            wrapper.axis = .horizontal
            wrapper.accessibilityIdentifier = toggleField.key
            return wrapper
        case .select(let selectField):
            // Stays a system pull-down button — the menu, the chevron and the
            // selection behaviour are all UIKit's (`native-controls`); only its
            // colour and font come from the palette.
            let button = UIButton(type: .system)
            button.applyThemedTint()
            button.accessibilityIdentifier = selectField.key
            button.showsMenuAsPrimaryAction = true
            button.changesSelectionAsPrimaryAction = true
            button.contentHorizontalAlignment = .leading
            var actions: [UIAction] = [
                UIAction(title: "—") { [weak self] _ in
                    guard let self, !self.isSyncingFromState else { return }
                    // Defence against re-entry through syncFromState, not a workaround for a specific control.
                    self.state.set(.null, for: selectField.key)
                }
            ]
            actions.append(contentsOf: selectField.options.map { option in
                UIAction(title: option.title) { [weak self] _ in
                    guard let self, !self.isSyncingFromState else { return }
                    // Defence against re-entry through syncFromState, not a workaround for a specific control.
                    self.state.set(.string(option.value), for: selectField.key)
                }
            })
            button.menu = UIMenu(children: actions)
            return button
        case .date(let dateField):
            return buildDateRow(for: dateField)
        case .readOnly(let readOnlyField):
            let label = UILabel()
            label.numberOfLines = 0
            label.accessibilityIdentifier = readOnlyField.key
            // `code` *is* the theme's monospaced role.
            let textRole: TextRole = readOnlyField.isMonospaced ? .code : .body
            label.observeTheme { label, palette in
                label.textColor = palette.primaryTextColor
                label.font = palette.font(textRole)
            }
            return label
        case .markdown(let markdownField):
            let key = markdownField.key
            let initialText = state.value(for: key).stringValue ?? ""
            let editor = markdownEditing.makeEditor(initialText: initialText) { [weak self] in
                self?.state.set(.string($0), for: key)
            }
            addChild(editor)
            editor.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
            return editor.view
        }
    }

    /// A `.date` row: picker, "Set date", "Clear". `UIDatePicker` has no empty state; it renders today
    /// for a null value, so the row shows the picker only when the model actually holds a date and
    /// offers "Set date" otherwise. `applyDateRow(key:value:isRequired:)` owns which of the three show.
    private func buildDateRow(for field: FormDateField) -> UIView {
        let key = field.key
        let picker = UIDatePicker()
        picker.accessibilityIdentifier = key
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .compact
        // `action.sender` rather than capturing `picker`, for the retain-cycle reason in
        // `makeTextField(key:placeholder:secure:)`.
        picker.addAction(UIAction { [weak self] action in
            guard let self, !self.isSyncingFromState else { return }
            // Defence against re-entry through syncFromState, not a workaround for a specific control.
            guard let picker = action.sender as? UIDatePicker else { return }
            self.state.set(.date(picker.date), for: key)
        }, for: .valueChanged)
        datePickers[key] = picker

        let setButton = UIButton(type: .system)
        setButton.applyThemedTint()
        setButton.setTitle("Set date", for: .normal)
        setButton.accessibilityIdentifier = key
        // Commits today's date immediately rather than just revealing the picker, so the value the row
        // starts displaying is the value the model holds; the bug this replaced was exactly that gap.
        setButton.addAction(UIAction { [weak self] _ in
            self?.state.set(.date(Date()), for: key)
        }, for: .touchUpInside)
        dateSetButtons[key] = setButton

        let clearButton = UIButton(type: .system)
        clearButton.applyThemedTint()
        clearButton.setTitle("Clear", for: .normal)
        clearButton.accessibilityIdentifier = key
        clearButton.addAction(UIAction { [weak self] _ in
            self?.state.set(.null, for: key)
        }, for: .touchUpInside)
        dateClearButtons[key] = clearButton

        let row = UIStackView(arrangedSubviews: [picker, setButton, clearButton, UIView()])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.accessibilityIdentifier = key
        return row
    }

    private func buildTextView(key: String, minLines: Int, monospaced: Bool) -> UIView {
        let textView = UITextView()
        let textRole: TextRole = monospaced ? .code : .body
        textView.observeTheme { textView, palette in
            textView.backgroundColor = palette.controlBackgroundColor
            textView.textColor = palette.primaryTextColor
            textView.tintColor = palette.cursorColor
            textView.font = palette.font(textRole)
            // Re-resolved on every apply, because a `CGColor` is a colour
            // already resolved — see `applyTextViewBorderColors`.
            textView.layer.borderColor = palette.borderColor
                .resolvedColor(with: textView.traitCollection).cgColor
        }
        textView.autocorrectionType = monospaced ? .no : .default
        borderedTextViews.append(textView)
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 6
        textView.delegate = self
        textView.accessibilityIdentifier = key
        textViewKeys[ObjectIdentifier(textView)] = key
        textView.heightAnchor.constraint(equalToConstant: CGFloat(minLines) * 20 + 12).isActive = true
        return textView
    }

    private func buildFooter() -> UIView {
        blockedLabel.observeTheme { label, palette in
            label.textColor = palette.secondaryTextColor
            label.font = palette.font(.caption)
        }
        for label in [errorLabel, actionErrorLabel] {
            label.observeTheme { label, palette in
                label.textColor = palette.dangerColor
                label.font = palette.font(.caption)
            }
            label.numberOfLines = 0
        }
        actionErrorLabel.isHidden = true
        saveButton.applyThemedTint()
        revertButton.applyThemedTint()
        saveButton.setTitle(state.spec.actions.save?.title ?? "Save", for: .normal)
        saveButton.addAction(UIAction { [weak self] _ in Task { await self?.performSave() } }, for: .touchUpInside)
        revertButton.setTitle("Revert", for: .normal)
        revertButton.addAction(UIAction { [weak self] _ in self?.revertTapped() }, for: .touchUpInside)
        deleteButton.setTitle(state.spec.actions.delete?.title ?? "Delete", for: .normal)
        deleteButton.applyThemedTint(.danger)
        deleteButton.isHidden = state.spec.actions.delete == nil
        deleteButton.addAction(UIAction { [weak self] _ in self?.deleteTapped() }, for: .touchUpInside)
        saveButton.isHidden = state.spec.actions.save == nil
        revertButton.isHidden = state.spec.actions.save == nil

        var views: [UIView] = [deleteButton]
        for action in state.spec.actions.extra {
            let button = UIButton(type: .system)
            button.applyThemedTint(action.isDestructive ? .danger : .accent)
            button.setTitle(action.title, for: .normal)
            button.accessibilityIdentifier = action.id
            button.addAction(UIAction { [weak self] _ in self?.runExtra(action) }, for: .touchUpInside)
            extraButtons[action.id] = button
            views.append(button)
        }
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        views.append(contentsOf: [spacer, revertButton, saveButton])
        let buttons = UIStackView(arrangedSubviews: views)
        buttons.axis = .horizontal
        buttons.spacing = 12
        let footer = UIStackView(arrangedSubviews: [blockedLabel, errorLabel, actionErrorLabel, buttons])
        footer.axis = .vertical
        footer.spacing = 6
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
            label?.text = state.errors[field.key]
            label?.isHidden = state.errors[field.key] == nil
        }
        saveButton.isEnabled = state.canSave
        revertButton.isEnabled = state.isDirty && !state.isSaving
        blockedLabel.text = state.blockedReason
        blockedLabel.isHidden = state.blockedReason == nil
        errorLabel.text = state.saveError
        errorLabel.isHidden = state.saveError == nil
    }

    private func syncControl(_ control: UIView, for field: FormField) {
        let value = state.value(for: field.key)
        switch (field, control) {
        case (.stringSet, let text as UITextField):
            text.text = (value.stringSetValue ?? []).joined(separator: ", ")
        case (.number, let text as UITextField):
            text.text = value.numberValue.map { numberFormatter.string(from: NSNumber(value: $0)) ?? "" } ?? ""
        case (.text, let text as UITextField):
            if text.text != value.stringValue ?? "" { text.text = value.stringValue ?? "" }
        case (.readOnly, let label as UILabel):
            label.text = value.stringValue ?? ""
        case (.toggle, let wrapper as UIStackView):
            (wrapper.arrangedSubviews.first as? UISwitch)?.isOn = value.boolValue ?? false
        case (.select(let selectField), let button as UIButton):
            applySelection(value.stringValue, to: button, options: selectField.options)
        case (.date(let dateField), _):
            applyDateRow(key: dateField.key, value: value, isRequired: dateField.isRequired)
        case (.textArea, let textView as UITextView), (.json, let textView as UITextView):
            if textView.text != value.stringValue ?? "" { textView.text = value.stringValue ?? "" }
        default:
            break
        }
    }

    /// Identifies the transient entry `applySelection` appends for a model value that is not in
    /// `options`, so the next sync can strip it back out before it counts the menu against `options`.
    private static let offListSelectionActionID = UIAction.Identifier("AgenticToolkit.HTDV.offListSelection")

    /// A `changesSelectionAsPrimaryAction` button derives its own title from whichever menu action is
    /// `.on`, and rewrites it on every menu interaction, so the manual `setTitle` this replaces was
    /// overwritten the first time the user opened the menu and the button then disagreed with the
    /// model (M5). Drive the action state and let UIKit own the title.
    ///
    /// The menu is REASSIGNED after the states are set. Mutating `UIAction.state` in place on a menu
    /// UIKit has already ingested is not documented to republish it, so a button built at
    /// `buildControl(for:)` with every action `.off` could keep an empty title while the model held a
    /// value. `replacingChildren(_:)` is the documented way to publish the change.
    ///
    /// A value that is not in `options` at all (a stale enum from the server) would leave EVERY action
    /// `.off`, and a `changesSelectionAsPrimaryAction` button with no selected action has nothing to
    /// title itself from — it renders blank, where the old `setTitle` path at least showed the raw
    /// value. A disabled action carrying that raw value stands in, so the button says what the model
    /// actually holds while still refusing to offer it as a choice; it is dropped again as soon as the
    /// value is back on the list.
    private func applySelection(_ selected: String?, to button: UIButton, options: [FormSelectOption]) {
        guard let children = button.menu?.children as? [UIAction] else { return }
        var actions = children.filter { $0.identifier != Self.offListSelectionActionID }
        guard actions.count == options.count + 1 else { return }
        // Index 0 is the "no selection" entry the menu is built with; the rest line up with `options`.
        let wanted = selected.flatMap { $0.isEmpty ? nil : $0 }
        actions[0].state = wanted == nil ? .on : .off
        var isOnTheList = false
        for (index, option) in options.enumerated() {
            let isSelected = option.value == wanted
            actions[index + 1].state = isSelected ? .on : .off
            isOnTheList = isOnTheList || isSelected
        }
        if let wanted, !isOnTheList {
            actions.append(UIAction(
                title: wanted, identifier: Self.offListSelectionActionID,
                attributes: [.disabled], state: .on
            ) { _ in })
        }
        button.menu = button.menu?.replacingChildren(actions)
    }

    /// Shows exactly one of "picker (+ Clear)" and "Set date", so the row never claims a date the model
    /// does not hold. A required field gets no Clear button: emptying it could only produce an error.
    private func applyDateRow(key: String, value: FormValue, isRequired: Bool) {
        let date = value.dateValue
        if let date { datePickers[key]?.date = date }
        datePickers[key]?.isHidden = date == nil
        dateSetButtons[key]?.isHidden = date != nil
        dateClearButtons[key]?.isHidden = date == nil || isRequired
    }

    // MARK: UI → State

    private func textFieldChanged(_ sender: UITextField) {
        // Defence against re-entry through syncFromState, not a workaround for a specific control.
        guard !isSyncingFromState, let key = sender.accessibilityIdentifier,
              let field = state.spec.fields.first(where: { $0.key == key }) else { return }
        // Deliberately identity, not first-responder state: `state.set` re-enters `syncFromState()`
        // synchronously, and the macOS twin's tests drive the equivalent entry point with no window
        // and no field editor, so a responder check would not hold there either.
        controlBeingEdited = sender
        defer { controlBeingEdited = nil }
        let raw = sender.text ?? ""
        switch field {
        case .number:
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            state.set(trimmed.isEmpty ? .null : (Double(trimmed).map { .number($0) } ?? .string(trimmed)), for: key)
        case .stringSet:
            let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            state.set(.stringSet(parts), for: key)
        default:
            state.set(.string(raw), for: key)
        }
    }

    public func textViewDidChange(_ textView: UITextView) {
        // Defence against re-entry through syncFromState, not a workaround for a specific control.
        guard !isSyncingFromState, let key = textViewKeys[ObjectIdentifier(textView)] else { return }
        state.set(.string(textView.text ?? ""), for: key)
    }

    // MARK: Footer actions

    func performSave() async {
        if await state.save() { onSaved() }
    }

    private func revertTapped() {
        state.revert()
        for field in state.spec.fields {
            guard case .markdown = field,
                  let editor = children.first(where: { $0.view === controls[field.key] }) else { continue }
            (editor as? MarkdownTextReplacing)?.replaceText(with: state.value(for: field.key).stringValue ?? "")
        }
    }

    private func deleteTapped() {
        Task { [weak self] in await self?.performDelete() }
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

    private func runExtra(_ action: FormAction) {
        Task { [weak self] in await self?.performExtra(id: action.id) }
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
        actionErrorLabel.text = nil
        actionErrorLabel.isHidden = true
    }

    private func showActionError(_ error: any Error) {
        actionErrorLabel.text = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        actionErrorLabel.isHidden = false
    }

    // MARK: HTDVDetailHosting

    public func confirmDiscard() async -> Bool {
        await confirmDiscardHandler()
    }
}
#endif
