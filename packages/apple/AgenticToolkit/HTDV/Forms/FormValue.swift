import Foundation

/// The value of one form field. Every field key maps to exactly one of these in `FormState.values`.
public enum FormValue: Hashable, Sendable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case date(Date)
    case stringSet([String])
    case null

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var dateValue: Date? {
        if case .date(let value) = self { return value }
        return nil
    }

    public var stringSetValue: [String]? {
        if case .stringSet(let value) = self { return value }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}
