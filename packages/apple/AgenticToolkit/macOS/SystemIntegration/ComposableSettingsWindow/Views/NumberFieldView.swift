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
    ///
    /// The `locale` is a parameter rather than a read of `Locale.current`
    /// because the behaviour that matters here is the behaviour on a machine
    /// the author is not sitting at: a test that leans on the process locale
    /// passes in en_US and proves nothing about de_DE.
    init?(settingsFieldString: String, locale: Locale)
    var settingsFieldString: String { get }
    /// Whether a decimal separator belongs in this kind of number. Read when
    /// parsing: it is what makes an `Int` field refuse `"1,5"` outright
    /// instead of quietly keeping the `1`.
    static var settingsAllowsFloats: Bool { get }
}

extension SettingsNumberValue {

    /// What the field itself calls: the same parse, in the locale the user is
    /// actually standing in.
    public init?(settingsFieldString text: String) {
        self.init(settingsFieldString: text, locale: .current)
    }

    /// The locale-aware half of the parse, tried **only** after the POSIX one
    /// has failed.
    ///
    /// The ordering is not a preference, it is the fix. `settingsFieldString`
    /// — the writer — is POSIX, and `sync()` puts its output back into the
    /// field. A locale-first parse would read the POSIX `"1.5"` that `sync()`
    /// itself just wrote, take the `.` for de_DE's grouping separator, and
    /// store 15: an untouched field would multiply its own value by ten on
    /// every commit cycle, and no en_US test run would ever show it. POSIX
    /// first also keeps what is stored and what is shown stable when the user
    /// changes locale, which matters because the value is stored numerically
    /// and re-rendered from scratch on every launch.
    ///
    /// A formatter per call rather than a cached one: `NumberFormatter` is a
    /// non-`Sendable` class and this is a `nonisolated` context on a value
    /// type, so a shared instance would need isolating. A human typing into a
    /// field is not a hot loop.
    static func settingsLocaleNumber(from text: String, locale: Locale) -> NSNumber? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.allowsFloats = settingsAllowsFloats
        return formatter.number(from: text)
    }
}

extension Int: SettingsNumberValue {
    public init?(settingsFieldString text: String, locale: Locale) {
        // Trimmed because a field's text arrives with whatever the user's
        // spacebar left in it, and `Int(" 12")` is nil.
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let posix = Int(trimmed) {
            self = posix
            return
        }
        guard let number = Self.settingsLocaleNumber(from: trimmed, locale: locale) else {
            return nil
        }
        // A fractional edit of an integer setting is rejected, not rounded.
        // `allowsFloats == false` above is the first refusal and this is the
        // second: whatever a locale makes of `"1,5"`, an integer field stores
        // an integer or it stores nothing, and a silent 1 or 2 is a value the
        // user did not type.
        let value = number.doubleValue
        guard value.isFinite, value == value.rounded(), let exact = Int(exactly: value) else {
            return nil
        }
        self = exact
    }

    public var settingsFieldString: String { String(self) }
    public static var settingsAllowsFloats: Bool { false }
}

extension Double: SettingsNumberValue {
    public init?(settingsFieldString text: String, locale: Locale) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let posix = Double(trimmed) {
            // `Double("nan")` and `Double("inf")` both parse. NaN then makes
            // every comparison in `commit()` false, so a bounded field accepts
            // an out-of-range value, `!=` is true forever and it rewrites on
            // every cycle, and the extension reads a NaN where its own schema
            // promised a range. It is a typo like any other.
            guard posix.isFinite else { return nil }
            self = posix
            return
        }
        guard let number = Self.settingsLocaleNumber(from: trimmed, locale: locale),
              number.doubleValue.isFinite else {
            return nil
        }
        self = number.doubleValue
    }

    /// A whole number is written without a fraction. `String(20.0)` is
    /// `"20.0"`, and a field that turns the `20` an extension author wrote
    /// into `20.0` the moment it is shown has edited a setting nobody touched.
    ///
    /// POSIX, deliberately — see `settingsLocaleNumber(from:locale:)` for why
    /// the writer stays that way while the reader learned a locale.
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

            // No formatter is attached to the field. A formatter with a
            // minimum rejects the intermediate text on the way to a valid
            // number — you cannot type "-" before "-5", and with a minimum of
            // 10 you cannot type the "1" of "12". Formatting is a parse on
            // commit instead (`SettingsNumberValue`), which refuses only
            // finished text and still reads what the user's locale writes.
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
