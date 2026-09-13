import Foundation

/// Mutable model behind a `FormViewController`: current values, baseline for dirty tracking, validation errors,
/// and the save lifecycle. UI-agnostic so it is fully unit-testable.
@MainActor
public final class FormState {
    public let spec: FormSpec
    public private(set) var values: [String: FormValue]
    public private(set) var errors: [String: String] = [:]
    /// When non-nil, saving is disabled and the reason is shown next to the save button (e.g. "Read-only member").
    public var blockedReason: String? {
        didSet { onChange(self) }
    }
    public private(set) var isSaving = false
    public private(set) var saveError: String?
    public var onChange: (FormState) -> Void = { _ in }

    private var baseline: [String: FormValue]
    private let fieldsByKey: [String: FormField]

    /// Field keys `spec` declares more than once, in first-seen order. `FormSpec.fields` flattens all
    /// sections, and every key-indexed map built from it — values here, controls in the view
    /// controllers — is last-write-wins, so an earlier duplicate renders but never syncs, never shows
    /// its validation error, and reads back the other field's value. Exposed as a pure function so the
    /// detection is testable; `init` only decides what to do about it.
    static func duplicateFieldKeys(in spec: FormSpec) -> [String] {
        var seen: Set<String> = []
        var duplicates: [String] = []
        for field in spec.fields where !seen.insert(field.key).inserted {
            if !duplicates.contains(field.key) { duplicates.append(field.key) }
        }
        return duplicates
    }

    public init(spec: FormSpec, values: [String: FormValue] = [:]) {
        self.spec = spec
        // `assertionFailure`, not `precondition`: a duplicate key is a spec-authoring bug that debug
        // builds should stop on, but a shipped app keeps today's last-write-wins render rather than
        // crashing on a form it could still mostly show.
        for key in Self.duplicateFieldKeys(in: spec) {
            assertionFailure("FormSpec declares field key \"\(key)\" more than once")
        }
        var initial: [String: FormValue] = [:]
        var byKey: [String: FormField] = [:]
        for field in spec.fields {
            initial[field.key] = values[field.key] ?? field.defaultValue
            byKey[field.key] = field
        }
        self.values = initial
        self.baseline = initial
        self.fieldsByKey = byKey
    }

    public var isDirty: Bool { values != baseline }

    public var canSave: Bool { spec.actions.save != nil && isDirty && blockedReason == nil && !isSaving }

    public func value(for key: String) -> FormValue { values[key] ?? .null }

    public func set(_ value: FormValue, for key: String) {
        guard let field = fieldsByKey[key] else { return }
        values[key] = value
        errors[key] = FormValidator.validate(field: field, value: value)
        saveError = nil
        onChange(self)
    }

    /// Validates every field, records the errors, and returns true when there are none.
    @discardableResult
    public func validateAll() -> Bool {
        var fresh: [String: String] = [:]
        for field in spec.fields {
            if let problem = FormValidator.validate(field: field, value: value(for: field.key)) {
                fresh[field.key] = problem
            }
        }
        errors = fresh
        onChange(self)
        return fresh.isEmpty
    }

    /// Validates, then runs the spec's save action. Returns true when the save completed.
    public func save() async -> Bool {
        guard let action = spec.actions.save, blockedReason == nil, !isSaving else { return false }
        guard validateAll() else { return false }
        isSaving = true
        saveError = nil
        onChange(self)
        let snapshot = values
        do {
            try await action.perform(snapshot)
            baseline = snapshot
            isSaving = false
            onChange(self)
            return true
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            isSaving = false
            onChange(self)
            return false
        }
    }

    public func revert() {
        values = baseline
        errors = [:]
        saveError = nil
        onChange(self)
    }

    /// Adopt the current values as the new baseline without performing the save action.
    public func markSaved() {
        baseline = values
        onChange(self)
    }
}
