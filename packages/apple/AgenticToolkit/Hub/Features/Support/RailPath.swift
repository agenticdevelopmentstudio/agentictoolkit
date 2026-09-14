import AgenticToolkitHTDV
import Foundation

/// Position helpers for the `[HTDVItem]` path a module receives in `child(for:)`.
public enum RailPath {
    public static func id(at index: Int, in path: [HTDVItem]) -> String? {
        guard path.indices.contains(index) else { return nil }
        return path[index].id
    }

    public static func last(_ path: [HTDVItem]) -> HTDVItem? { path.last }
}
