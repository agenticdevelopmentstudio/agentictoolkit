import AppKit
import Foundation

/// The one place these commands turn a dictionary into the string an
/// AppleScript command returns.
///
/// `JSONSerialization` rather than `Encodable`, because the values here are
/// heterogeneous by nature — a window's entry holds a number, a string, three
/// booleans and a nested frame — and a `Codable` wrapper per shape would be
/// four more types that exist only to be encoded once.
public enum ScriptJSON {
    public static func frame(_ rect: NSRect) -> [String: Double] {
        [
            "x": Double(rect.origin.x),
            "y": Double(rect.origin.y),
            "width": Double(rect.size.width),
            "height": Double(rect.size.height)
        ]
    }

    /// Sorted keys so two snapshots can be diffed textually; pretty so a person
    /// reading one in a terminal can. `"{}"` on failure: every caller's JSON
    /// parser already handles an empty object, and none of them handles a
    /// thrown error.
    public static func string(from object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
