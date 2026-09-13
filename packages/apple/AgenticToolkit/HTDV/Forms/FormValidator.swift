import Foundation

/// Field-level validation. Returns the first problem as a user-facing message, or nil when the value is acceptable.
public enum FormValidator {
    /// - Parameter locale: formats the numeric bounds quoted in min/max messages. Defaults to the
    ///   ambient locale, which is the right user-facing behaviour — a comma-decimal user should read
    ///   "at least 2,5" — and is injectable so a test can assert a shape instead of rebuilding its own
    ///   expectation through the very formatter it is testing.
    public static func validate(field: FormField, value: FormValue, locale: Locale = .current) -> String? {
        switch field {
        case .text(let textField):
            return validateText(
                value, label: textField.label, isRequired: textField.isRequired,
                pattern: textField.pattern, message: textField.patternMessage
            )
        case .textArea(let textAreaField):
            return validateText(
                value, label: textAreaField.label, isRequired: textAreaField.isRequired, pattern: nil, message: nil
            )
        case .markdown(let markdownField):
            return validateText(
                value, label: markdownField.label, isRequired: markdownField.isRequired, pattern: nil, message: nil
            )
        case .json(let jsonField):
            if let problem = validateText(
                value, label: jsonField.label, isRequired: jsonField.isRequired, pattern: nil, message: nil
            ) {
                return problem
            }
            return validateJSON(value, label: jsonField.label)
        case .toggle, .readOnly, .date:
            if case .date(let dateField) = field, dateField.isRequired, value.dateValue == nil {
                return "\(dateField.label) is required"
            }
            return nil
        case .select(let selectField):
            guard let chosen = value.stringValue, !chosen.isEmpty else {
                return selectField.isRequired ? "\(selectField.label) is required" : nil
            }
            return selectField.options.contains { $0.value == chosen }
                ? nil : "\(selectField.label) must be one of the listed options"
        case .number(let numberField):
            return validateNumber(value, field: numberField, locale: locale)
        case .stringSet(let stringSetField):
            let items = value.stringSetValue ?? []
            return stringSetField.isRequired && items.isEmpty ? "\(stringSetField.label) is required" : nil
        }
    }

    private static func validateText(
        _ value: FormValue, label: String, isRequired: Bool, pattern: String?, message: String?
    ) -> String? {
        let text = value.stringValue ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return isRequired ? "\(label) is required" : nil }
        // `FormTextField.pattern` is documented as a pattern the WHOLE value must match, but
        // `range(of:options:.regularExpression)` succeeds on any substring, so an unanchored
        // pattern would accept "My Slug!! (draft)" on the strength of the embedded "raft".
        // Anchoring here (rather than asking every caller to write `^…$`) keeps the documented
        // contract true for the natural way to write a pattern. Already-anchored patterns are
        // unaffected: `^(?:^[a-z]+$)$` still matches exactly what `^[a-z]+$` did.
        if let pattern, text.range(of: "^(?:\(pattern))$", options: .regularExpression) == nil {
            return message ?? "\(label) has an invalid format"
        }
        return nil
    }

    private static func validateNumber(_ value: FormValue, field: FormNumberField, locale: Locale) -> String? {
        guard let number = value.numberValue else {
            return field.isRequired ? "\(field.label) is required" : nil
        }
        if field.isInteger, number.rounded() != number { return "\(field.label) must be a whole number" }
        if let minimum = field.minimum, number < minimum {
            return "\(field.label) must be at least \(format(minimum, locale: locale))"
        }
        if let maximum = field.maximum, number > maximum {
            return "\(field.label) must be at most \(format(maximum, locale: locale))"
        }
        return nil
    }

    private static func validateJSON(_ value: FormValue, label: String) -> String? {
        let text = value.stringValue ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
            return "\(label) must be valid JSON"
        }
        return nil
    }

    /// Formats a bound for an error message. Deliberately not `String(Int(number))`: `Int(_:)` traps
    /// rather than saturating, so a spec with `maximum: 1e19` used to crash while BUILDING the
    /// message that reports the violation. A decimal `NumberFormatter` keeps the existing
    /// "whole numbers print without a decimal point" behaviour (1.0 → "1") for every finite value.
    /// Built per call rather than cached in a `static let`, which a non-`Sendable` `NumberFormatter`
    /// cannot be under strict concurrency; this is an error path, so it is never hot.
    /// The locale is threaded in rather than left ambient so the decimal separator is a stated input:
    /// the message is deliberately locale-aware (a `de_DE` user reads "2,5"), which makes it untestable
    /// against a hard-coded string unless the caller can pin the locale.
    private static func format(_ number: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 15
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
}
