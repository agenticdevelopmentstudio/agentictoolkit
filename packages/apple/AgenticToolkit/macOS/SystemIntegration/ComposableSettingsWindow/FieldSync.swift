import AppKit

extension ComposableSettings {

    /// How a record pane puts stored values back into its fields — one policy
    /// for every pane that shows a record which can change under it.
    ///
    /// - `load` is a refresh: it leaves alone a field the user is typing in, so
    ///   a poll that lands mid-word never replaces what is being typed.
    /// - `force` is a revert after a save that was refused: the text in that
    ///   field is exactly what failed, so it is discarded — editor and all, so
    ///   ending the edit later can't send it again.
    @MainActor
    public enum FieldSync {

        /// Shows `value` unless the field is being edited.
        public static func load(_ field: NSTextField, _ value: String) {
            guard field.currentEditor() == nil, field.stringValue != value else { return }
            field.stringValue = value
        }

        /// Shows `value`, discarding an edit in progress.
        public static func force(_ field: NSTextField, _ value: String) {
            if field.currentEditor() != nil { field.abortEditing() }
            if field.stringValue != value { field.stringValue = value }
        }

        /// Shows `value` unless the text view has focus.
        public static func load(_ textView: NSTextView, _ value: String) {
            guard textView.window?.firstResponder !== textView, textView.string != value else { return }
            textView.string = value
        }

        /// Shows `value`, whatever is being typed.
        public static func force(_ textView: NSTextView, _ value: String) {
            if textView.string != value { textView.string = value }
        }

        /// Selects the item whose `representedObject` is `value` — never by
        /// title, which two records can share.
        public static func select(_ value: String, in popup: NSPopUpButton) {
            let index = popup.itemArray.firstIndex { ($0.representedObject as? String) == value } ?? -1
            if popup.indexOfSelectedItem != index { popup.selectItem(at: index) }
        }
    }
}
