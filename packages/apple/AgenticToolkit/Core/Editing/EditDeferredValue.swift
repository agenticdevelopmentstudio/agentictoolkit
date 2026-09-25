import Foundation

/// A replacement value that must wait while an in-place edit is in flight.
///
/// A table that edits its cells in place cannot swap its rows out from under a
/// live field editor: the replacement lands before `reloadData`, and the end of
/// the edit then reads the *new* rows at the field's *old* index. So a reload
/// that arrives mid-edit is parked here and handed back when the edit ends.
///
/// One type rather than a flag and an optional per table, so a fix to *when* a
/// held reload is released reaches every table built this way (`dry`).
public struct EditDeferredValue<Value> {

    /// True between `beginEditing()` and `endEditing()`.
    public private(set) var isEditing = false

    /// The latest value offered while editing, if any.
    public private(set) var pending: Value?

    /// No edit in flight and nothing held.
    public init() {}

    /// Marks an edit as in flight; later offers are held until it ends.
    public mutating func beginEditing() {
        isEditing = true
    }

    /// Offers a replacement. Returns it when it may be applied now, or nil when
    /// an edit is in flight — in which case it replaces any earlier held value,
    /// because only the newest reload is worth applying.
    public mutating func offer(_ value: Value) -> Value? {
        guard isEditing else { return value }
        pending = value
        return nil
    }

    /// Ends the edit and returns the value that was held back, if any. Safe to
    /// call when no edit is in flight: it answers nil the second time.
    public mutating func endEditing() -> Value? {
        isEditing = false
        defer { pending = nil }
        return pending
    }
}
