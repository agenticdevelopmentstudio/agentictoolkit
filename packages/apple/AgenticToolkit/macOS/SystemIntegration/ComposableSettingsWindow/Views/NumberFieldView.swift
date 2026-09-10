import AppKit
import AgenticToolkitCore

/// A number a settings field can show, read back, and compare.
///
/// A protocol rather than a `BinaryInteger`/`BinaryFloatingPoint` pair because
/// the field needs exactly three things of a number — how it is written, how it
/// is read, and whether a decimal point belongs in it — and a protocol that
/// asks for only those can be conformed to by a type this framework has never
/// heard of.
///
/// At file scope because Swift does not allow a protocol to be nested inside
/// another declaration; the view it exists for is nested under
/// `ComposableSettings` like every other row.
public protocol SettingsNumberValue: Codable, Sendable, Comparable {
    /// The value a field's text stands for, or `nil` when the text is not a
    /// number of this kind. `nil` is what makes the field revert rather than
    /// store a zero the user never typed.
    init?(settingsFieldString: String)
    var settingsFieldString: String { get }
    static var settingsAllowsFloats: Bool { get }
}

extension Int: SettingsNumberValue {
    public init?(settingsFieldString: String) {
        // Trimmed because a field's text arrives with whatever the user's
        // spacebar left in it, and `Int(" 12")` is nil.
        self.init(settingsFieldString.trimmingCharacters(in: .whitespaces))
    }

    public var settingsFieldString: String { String(self) }
    public static var settingsAllowsFloats: Bool { false }
}

extension Double: SettingsNumberValue {
    public init?(settingsFieldString: String) {
        self.init(settingsFieldString.trimmingCharacters(in: .whitespaces))
    }

    /// A whole number is written without a fraction. `String(20.0)` is
    /// `"20.0"`, and a field that turns the `20` an extension author wrote
    /// into `20.0` the moment it is shown has edited a setting nobody touched.
    public var settingsFieldString: String {
        guard self == self.rounded(), let exact = Int(exactly: self) else { return String(self) }
        return String(exact)
    }

    public static var settingsAllowsFloats: Bool { true }
}

extension ComposableSettings {

    /// A short label and a narrow number field, clamped to whichever bounds
    /// were supplied.
    ///
    /// Optional bounds are the whole reason this exists: every other numeric
    /// row here is built on `RangeViewModel`, which requires both, and three
    /// quarters of the numeric settings a VS Code extension declares name
    /// neither. A number with no ceiling is still a number, not a text box.
    @MainActor
    public final class NumberFieldView<Value: SettingsNumberValue>:
        NSView, SettingsViewProtocol, NSTextFieldDelegate {

        public let label: NSTextField
        public let textField: NSTextField

        public let minimum: Value?
        public let maximum: Value?

        private let viewModel: ViewModel<Value>

        /// - Parameters:
        ///   - minimum: The lowest value the field will store, or `nil` to
        ///     clamp nothing at the bottom.
        ///   - maximum: The highest, or `nil`.
        ///   - fieldWidth: Width of the number field.
        ///   - labelWidth: When set, the label is pinned to this width and
        ///     right-aligned. That is what lets a *column* of these read as one
        ///     form — four sides of a padding box, say — with the fields lined
        ///     up under each other instead of stepping in and out with the
        ///     length of each name.
        public init(
            viewModel: ViewModel<Value>,
            minimum: Value? = nil,
            maximum: Value? = nil,
            fieldWidth: CGFloat = 72,
            labelWidth: CGFloat? = nil
        ) {
            self.viewModel = viewModel
            self.minimum = minimum
            self.maximum = maximum
            self.label = ComposableSettings.makeRowLabel(viewModel.title)
            self.textField = NSTextField()

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            // No `NumberFormatter`. A formatter with a minimum rejects the
            // intermediate text on the way to a valid number — you cannot type
            // "-" before "-5", and with a minimum of 10 you cannot type the
            // "1" of "12" — and one with `allowsFloats = false` silently
            // decides what a locale's decimal separator meant. Parsing on
            // commit and reverting on nonsense refuses less and loses nothing.
            self.textField.alignment = .right
            self.textField.stringValue = viewModel.value.settingsFieldString
            self.textField.target = self
            self.textField.action = #selector(fieldChanged(_:))
            self.textField.delegate = self
            self.textField.observeTheme { field, palette in
                field.font = palette.font(.code)
                field.textColor = palette.primaryTextColor
            }
            self.textField.setAccessibilityTitleUIElement(self.label)

            let row = Self.makeRow([self.label, self.textField])
            self.addSubview(row)

            NSLayoutConstraint.activate([
                self.textField.widthAnchor.constraint(equalToConstant: fieldWidth)
            ])

            if let labelWidth {
                self.label.alignment = .right
                self.label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
                // Content-width row rather than a pinned one: pinned to both
                // edges the stack would spread its two fixed-width children
                // across whatever the panel is wide, and the field would drift
                // away from the label it belongs to.
                NSLayoutConstraint.activate([
                    row.topAnchor.constraint(equalTo: self.topAnchor),
                    row.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                    row.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                    row.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor)
                ])
            } else {
                Self.pinToEdges(row, of: self)
            }

            viewModel.onChange = { [weak self] _ in self?.sync() }
            self.sync()
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame frameRect: NSRect)")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func sync() {
            label.stringValue = viewModel.title
            textField.stringValue = viewModel.value.settingsFieldString
        }

        /// Committing on every keystroke would fight the user mid-number (a "1"
        /// on the way to "12"), so the value is written when editing ends —
        /// which covers Return, Tab and clicking away.
        public func controlTextDidEndEditing(_ obj: Notification) {
            commit()
        }

        @objc private func fieldChanged(_ sender: NSTextField) {
            commit()
        }

        /// Reads the field, clamps it to whatever bounds exist, and stores it.
        ///
        /// Public so a test can commit without a window and a run loop — the
        /// same reason `TextAreaEditView.commit()` is.
        public func commit() {
            // Text that is not a number of this type is not a zero; it is a
            // typo. Put the stored value back and say nothing.
            guard let typed = Value(settingsFieldString: textField.stringValue) else {
                sync()
                return
            }
            var clamped = typed
            if let minimum, clamped < minimum { clamped = minimum }
            if let maximum, clamped > maximum { clamped = maximum }

            let text = clamped.settingsFieldString
            if textField.stringValue != text {
                textField.stringValue = text
            }
            if viewModel.settingObserver.value != clamped {
                viewModel.settingObserver.value = clamped
            }
        }
    }
}
