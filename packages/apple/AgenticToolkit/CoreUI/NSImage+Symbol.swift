import AppKit

extension NSImage {

    /// An SF Symbol that is never nil.
    ///
    /// `NSImage(systemSymbolName:)` answers nil for a misspelled name or a
    /// symbol this macOS does not ship, and a force-unwrap turns that into a
    /// crash in whatever view happened to build the button. This answers a
    /// blank template image of symbol size instead, so the control still lays
    /// out and still carries its accessibility description.
    public static func symbol(named name: String, accessibilityDescription: String?) -> NSImage {
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription) {
            return image
        }
        let blank = NSImage(size: NSSize(width: 16, height: 16))
        blank.isTemplate = true
        blank.accessibilityDescription = accessibilityDescription
        return blank
    }
}
