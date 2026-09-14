import Foundation

/// A JSON document as a value type, for fields the backend types as free-form JSON (bag values, metadata,
/// template vars).
public enum JSONValue: Codable, Hashable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case int(Int64)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let bool = try? container.decode(Bool.self) { self = .bool(bool); return }
        if let int = try? container.decode(Int64.self) { self = .int(int); return }
        if let number = try? container.decode(Double.self) { self = .number(number); return }
        if let string = try? container.decode(String.self) { self = .string(string); return }
        if let array = try? container.decode([JSONValue].self) { self = .array(array); return }
        if let object = try? container.decode([String: JSONValue].self) { self = .object(object); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let object): try container.encode(object)
        case .array(let array): try container.encode(array)
        case .string(let string): try container.encode(string)
        case .int(let int): try container.encode(int)
        case .number(let number): try container.encode(number)
        case .bool(let bool): try container.encode(bool)
        case .null: try container.encodeNil()
        }
    }

    /// Pretty-printed with sorted keys, so form text is stable between loads.
    public var prettyText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return text
    }

    public static func parse(_ text: String) throws -> JSONValue {
        do {
            return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        } catch let error as DecodingError {
            throw HubError.validation("Invalid JSON: \(error.decodingDebugDescription)")
        } catch {
            throw HubError.validation("Invalid JSON: \(error.localizedDescription)")
        }
    }

    // MARK: Equality
    //
    // Hand-written because the SYNTHESIZED enum equality compares cases first, and `.int` and `.number`
    // are two spellings of the same JSON number. `.number(20)` encodes to `20`, decodes back as
    // `.int(20)`, and synthesized `==` called that a change — so a form's `isDirty` baseline comparison
    // misfired: Save enabled on an untouched form, spurious discard prompts on the way out.

    /// True when `value` is the same JSON number as `int`, at full `Int64` precision.
    private static func sameNumber(_ int: Int64, _ value: Double) -> Bool {
        Int64(exactly: value) == int
    }

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.object(let left), .object(let right)): left == right
        case (.array(let left), .array(let right)): left == right
        case (.string(let left), .string(let right)): left == right
        case (.int(let left), .int(let right)): left == right
        case (.number(let left), .number(let right)): left == right
        case (.int(let left), .number(let right)): sameNumber(left, right)
        case (.number(let left), .int(let right)): sameNumber(right, left)
        case (.bool(let left), .bool(let right)): left == right
        case (.null, .null): true
        default: false
        }
    }

    /// Numbers hash on their canonical form — an integral `.number` hashes as the `.int` it equals —
    /// or `Hashable`'s contract breaks the moment `==` treats the two cases as one.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .object(let object): hasher.combine(0); hasher.combine(object)
        case .array(let array): hasher.combine(1); hasher.combine(array)
        case .string(let string): hasher.combine(2); hasher.combine(string)
        case .int(let int): hasher.combine(3); hasher.combine(int)
        case .number(let number):
            if let exact = Int64(exactly: number) {
                hasher.combine(3); hasher.combine(exact)
            } else {
                hasher.combine(4); hasher.combine(number)
            }
        case .bool(let bool): hasher.combine(5); hasher.combine(bool)
        case .null: hasher.combine(6)
        }
    }

    public var stringDictionary: [String: String]? {
        guard case .object(let object) = self else { return nil }
        var out: [String: String] = [:]
        for (key, value) in object {
            guard case .string(let string) = value else { return nil }
            out[key] = string
        }
        return out
    }
}

extension DecodingError {
    /// `localizedDescription` is a generic, NSError-backed message that names nothing; every case here
    /// carries a `Context` whose `debugDescription` names the failing position, which is what a
    /// user-visible parse error should show instead.
    var decodingDebugDescription: String {
        switch self {
        case .typeMismatch(_, let context): return context.debugDescription
        case .valueNotFound(_, let context): return context.debugDescription
        case .keyNotFound(_, let context): return context.debugDescription
        case .dataCorrupted(let context): return context.debugDescription
        @unknown default: return String(describing: self)
        }
    }
}
