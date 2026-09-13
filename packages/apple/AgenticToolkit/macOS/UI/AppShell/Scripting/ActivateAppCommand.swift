import AppKit

/// AppleScript command: `activate` — brings the host app to the front.
/// Lives in the toolkit because it's pure app-shell behaviour with no
/// feature coupling.
@objc(ActivateAppCommand)
public final class ActivateAppCommand: MainActorScriptCommand, @unchecked Sendable {
    public override func performMain() -> Any? {
        NSApp.activateUnlessQuiet()
        return nil
    }
}
