import AppKit

public extension NSApplication {

    /// Bring the app to the front — unless this process was told to keep its
    /// hands off the foreground.
    ///
    /// Showing a window and *activating the app* are two different acts, and a
    /// menubar (LSUIElement) host needs both: `orderFrontRegardless()` puts one
    /// window above other applications' windows, but until the app is active
    /// the menu bar still belongs to somebody else and so does the next
    /// keystroke. A window the user asked for that they then have to click to
    /// type into came up in the background, whatever it looks like.
    ///
    /// So every "the user asked for this window" path activates, and this is
    /// the single place that knows when not to. `QuietWindowPresentation` is
    /// off in a shipping build and off in a Debug build nobody passed
    /// `-QuietWindowPresentation YES` to, which is to say: off whenever a
    /// person is the one asking. It is on under XCTest and under an automated
    /// session, and those are exactly the two callers that must never take a
    /// screen someone else is working on.
    ///
    /// Written once rather than at each call site because it had been written
    /// at each call site: eleven of them called `activate(ignoringOtherApps:)`
    /// bare, so the flag was honoured by the windows that happened to remember
    /// it and ignored by the rest.
    func activateUnlessQuiet() {
        guard !QuietWindowPresentation.isEnabled else { return }
        activate(ignoringOtherApps: true)
    }
}
