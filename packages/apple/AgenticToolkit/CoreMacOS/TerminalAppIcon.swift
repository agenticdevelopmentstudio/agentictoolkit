import AppKit

/// The icon of the terminal application a session is running in, from the
/// `TERM_PROGRAM` the shell reported.
///
/// Two surfaces show the same fact — the Sessions list heads each row with it,
/// and a row in the Conversations feed carries it as the way back to the
/// session — so the mapping and the fallbacks are here rather than in whichever
/// one needed them first. Getting a different icon for the same terminal in two
/// windows is the kind of drift a reader reads as two different terminals.
public enum TerminalAppIcon {

    /// `TERM_PROGRAM` values, as the shells set them, to the bundle identifiers
    /// that name the same applications to LaunchServices. `tmux` reports itself
    /// rather than whatever it is running inside, and Terminal is the honest
    /// guess for it.
    private static let bundleIDs: [String: String] = [
        "iTerm.app": "com.googlecode.iterm2",
        "Apple_Terminal": "com.apple.Terminal",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "vscode": "com.microsoft.VSCode",
        "tmux": "com.apple.Terminal"
    ]

    /// Prefers a *running* instance's icon — which is the one the user is
    /// looking at, badges and all — falls back to the installed bundle, and
    /// then to a generic terminal glyph for a terminal we have no name for — so
    /// a row is left without an icon only if the system symbol itself is
    /// missing, which is why the result is still optional.
    public static func image(forTermProgram termProgram: String) -> NSImage? {
        if let bundleID = bundleIDs[termProgram] {
            if let running = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).first?.icon {
                return running
            }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        return NSImage(systemSymbolName: "terminal", accessibilityDescription: "terminal")
    }
}
