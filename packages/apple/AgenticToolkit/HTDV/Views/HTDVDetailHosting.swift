import Foundation

/// Detail view controllers that can hold unsaved edits adopt this so the rail host can confirm before
/// replacing them. `FormViewController` conforms; custom detail panes may too.
public protocol HTDVDetailHosting: AnyObject {
    @MainActor var hasUnsavedChanges: Bool { get }
    /// Ask the user whether to discard. Returns true when it is OK to proceed.
    @MainActor func confirmDiscard() async -> Bool
}
