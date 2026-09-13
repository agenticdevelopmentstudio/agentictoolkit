import Foundation

// MARK: - Spec

/// Declarative description of a detail form: sections of fields plus the actions the footer offers.
public struct FormSpec: Sendable {
    public var sections: [FormSection]
    public var actions: FormActions

    public init(sections: [FormSection], actions: FormActions = FormActions()) {
        self.sections = sections
        self.actions = actions
    }

    /// All fields in display order.
    public var fields: [FormField] { sections.flatMap(\.fields) }
}

public struct FormSection: Sendable {
    public var title: String?
    public var fields: [FormField]

    public init(title: String? = nil, fields: [FormField]) {
        self.title = title
        self.fields = fields
    }
}

// MARK: - Fields

public enum FormField: Sendable {
    case text(FormTextField)
    case textArea(FormTextAreaField)
    case toggle(FormToggleField)
    case select(FormSelectField)
    case number(FormNumberField)
    case date(FormDateField)
    case stringSet(FormStringSetField)
    case readOnly(FormReadOnlyField)
    case markdown(FormMarkdownField)
    case json(FormJSONField)

    public var key: String {
        switch self {
        case .text(let textField): textField.key
        case .textArea(let textAreaField): textAreaField.key
        case .toggle(let toggleField): toggleField.key
        case .select(let selectField): selectField.key
        case .number(let numberField): numberField.key
        case .date(let dateField): dateField.key
        case .stringSet(let stringSetField): stringSetField.key
        case .readOnly(let readOnlyField): readOnlyField.key
        case .markdown(let markdownField): markdownField.key
        case .json(let jsonField): jsonField.key
        }
    }

    public var label: String {
        switch self {
        case .text(let textField): textField.label
        case .textArea(let textAreaField): textAreaField.label
        case .toggle(let toggleField): toggleField.label
        case .select(let selectField): selectField.label
        case .number(let numberField): numberField.label
        case .date(let dateField): dateField.label
        case .stringSet(let stringSetField): stringSetField.label
        case .readOnly(let readOnlyField): readOnlyField.label
        case .markdown(let markdownField): markdownField.label
        case .json(let jsonField): jsonField.label
        }
    }

    /// The value a `FormState` starts with when the caller supplies none.
    public var defaultValue: FormValue {
        switch self {
        case .text, .textArea, .markdown, .json, .readOnly: .string("")
        case .toggle: .bool(false)
        case .select, .number, .date: .null
        case .stringSet: .stringSet([])
        }
    }

    public var isEditable: Bool {
        if case .readOnly = self { return false }
        return true
    }
}

public struct FormTextField: Sendable {
    public var key: String
    public var label: String
    public var placeholder: String?
    public var isRequired: Bool
    public var isSecure: Bool
    /// NSRegularExpression pattern the whole value must match (checked only when non-empty).
    public var pattern: String?
    public var patternMessage: String?

    public init(
        key: String, label: String, placeholder: String? = nil, isRequired: Bool = false,
        isSecure: Bool = false, pattern: String? = nil, patternMessage: String? = nil
    ) {
        self.key = key
        self.label = label
        self.placeholder = placeholder
        self.isRequired = isRequired
        self.isSecure = isSecure
        self.pattern = pattern
        self.patternMessage = patternMessage
    }
}

public struct FormTextAreaField: Sendable {
    public var key: String
    public var label: String
    public var placeholder: String?
    public var isRequired: Bool
    public var minLines: Int

    public init(
        key: String, label: String, placeholder: String? = nil, isRequired: Bool = false, minLines: Int = 4
    ) {
        self.key = key
        self.label = label
        self.placeholder = placeholder
        self.isRequired = isRequired
        self.minLines = minLines
    }
}

public struct FormToggleField: Sendable {
    public var key: String
    public var label: String
    public var help: String?

    public init(key: String, label: String, help: String? = nil) {
        self.key = key
        self.label = label
        self.help = help
    }
}

public struct FormSelectOption: Hashable, Sendable {
    public var value: String
    public var title: String

    public init(value: String, title: String) {
        self.value = value
        self.title = title
    }
}

public struct FormSelectField: Sendable {
    public var key: String
    public var label: String
    public var options: [FormSelectOption]
    public var isRequired: Bool

    public init(key: String, label: String, options: [FormSelectOption], isRequired: Bool = false) {
        self.key = key
        self.label = label
        self.options = options
        self.isRequired = isRequired
    }
}

public struct FormNumberField: Sendable {
    public var key: String
    public var label: String
    public var minimum: Double?
    public var maximum: Double?
    public var isInteger: Bool
    public var isRequired: Bool

    public init(
        key: String, label: String, minimum: Double? = nil, maximum: Double? = nil,
        isInteger: Bool = false, isRequired: Bool = false
    ) {
        self.key = key
        self.label = label
        self.minimum = minimum
        self.maximum = maximum
        self.isInteger = isInteger
        self.isRequired = isRequired
    }
}

public struct FormDateField: Sendable {
    public var key: String
    public var label: String
    public var isRequired: Bool

    public init(key: String, label: String, isRequired: Bool = false) {
        self.key = key
        self.label = label
        self.isRequired = isRequired
    }
}

public struct FormStringSetField: Sendable {
    public var key: String
    public var label: String
    public var placeholder: String?
    public var isRequired: Bool

    public init(key: String, label: String, placeholder: String? = nil, isRequired: Bool = false) {
        self.key = key
        self.label = label
        self.placeholder = placeholder
        self.isRequired = isRequired
    }
}

public struct FormReadOnlyField: Sendable {
    public var key: String
    public var label: String
    public var isMonospaced: Bool

    public init(key: String, label: String, isMonospaced: Bool = false) {
        self.key = key
        self.label = label
        self.isMonospaced = isMonospaced
    }
}

public struct FormMarkdownField: Sendable {
    public var key: String
    public var label: String
    public var isRequired: Bool

    public init(key: String, label: String, isRequired: Bool = false) {
        self.key = key
        self.label = label
        self.isRequired = isRequired
    }
}

public struct FormJSONField: Sendable {
    public var key: String
    public var label: String
    public var isRequired: Bool

    public init(key: String, label: String, isRequired: Bool = false) {
        self.key = key
        self.label = label
        self.isRequired = isRequired
    }
}

// MARK: - Actions

/// A footer button. `perform` receives the current values (already validated when it is the save action).
public struct FormAction: Sendable {
    public var id: String
    public var title: String
    public var isDestructive: Bool
    public var perform: @Sendable ([String: FormValue]) async throws -> Void

    public init(
        id: String, title: String, isDestructive: Bool = false,
        perform: @escaping @Sendable ([String: FormValue]) async throws -> Void
    ) {
        self.id = id
        self.title = title
        self.isDestructive = isDestructive
        self.perform = perform
    }
}

public struct FormDeleteAction: Sendable {
    public var title: String
    /// Shown in the confirmation dialog; when nil the dialog uses "This cannot be undone."
    public var confirmationText: String?
    public var perform: @Sendable () async throws -> Void

    public init(
        title: String, confirmationText: String? = nil, perform: @escaping @Sendable () async throws -> Void
    ) {
        self.title = title
        self.confirmationText = confirmationText
        self.perform = perform
    }
}

public struct FormActions: Sendable {
    public var save: FormAction?
    public var delete: FormDeleteAction?
    public var extra: [FormAction]

    public init(save: FormAction? = nil, delete: FormDeleteAction? = nil, extra: [FormAction] = []) {
        self.save = save
        self.delete = delete
        self.extra = extra
    }
}
