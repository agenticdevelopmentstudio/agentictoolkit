import AppKit

/// Every pane command answers the same first question — "is there a pane with
/// that id?" — and every one of them has to be able to say *no* in a way a
/// script can tell apart from a legitimate answer.
///
/// `zoom pane` returns a boolean and `minimize pane` returns an edge name, so
/// "there is no such pane" and "the pane is not zoomed" / "the pane is not
/// minimized" are the same value on the wire. Cocoa Scripting has a channel
/// for exactly this, and this is where these commands use it.
///
/// `errAENoSuchObject` (-1728) is the code AppleScript itself raises for a
/// specifier that resolves to nothing — `pane id "nope"` produces it without
/// any help from us — so a script that already handles a missing pane handles
/// these commands' failure with the same `on error number -1728`. The Cocoa
/// alternative, `NSReceiverEvaluationScriptError`, is 1: a number in Cocoa's
/// own small error space that means nothing to a script author reading
/// `osascript` output.
private extension NSScriptCommand {

    func reportNoSuchPane(id identifier: String?) {
        self.scriptErrorNumber = Int(errAENoSuchObject)
        self.scriptErrorString = "No pane with id \"\(identifier ?? "")\"."
    }
}

/// `close pane "<id>"`.
///
/// The direct parameter is a pane id rather than a specifier, matching the
/// commands this app already has (`send message`, `new terminal session`).
/// A script that has a pane object has its id; a script that has only an id
/// does not have to build a specifier to use it.
///
/// Returns whether the pane is *gone*, not whether the request was delivered.
/// The tree may legitimately decline — the layout spec vetoes a tab's last pane
/// and any fixed region — and that refusal reaches the script as `false`, not
/// as an error: it is a real answer to a real question, and the error channel
/// stays reserved for a pane that does not exist. `zoom pane` and
/// `minimize pane` already read their post-state back the same way.
@objc(ClosePaneCommand)
public final class ClosePaneCommand: MainActorScriptCommand, @unchecked Sendable {

    public override func performMain() -> Any? {
        let identifier = self.directParameter as? String
        guard let identifier,
              let pane = ProjectWindowManager.shared.scriptablePane(uniqueID: identifier) else {
            // The result stays `false` — the sdef asks "was there such a pane?"
            // and `false` is the honest answer — but a script that asked to
            // close something that is not there has made a mistake, and the
            // error is what says so out loud.
            self.reportNoSuchPane(id: identifier)
            return false
        }
        pane.closePane()
        return !pane.isInWindow
    }
}

/// `zoom pane "<id>"` — returns the zoom state afterwards, so a script can
/// toggle and check in one step.
@objc(ZoomPaneCommand)
public final class ZoomPaneCommand: MainActorScriptCommand, @unchecked Sendable {

    public override func performMain() -> Any? {
        let identifier = self.directParameter as? String
        guard let identifier,
              let pane = ProjectWindowManager.shared.scriptablePane(uniqueID: identifier) else {
            self.reportNoSuchPane(id: identifier)
            return false
        }
        pane.zoomPane()
        return pane.paneZoomed
    }
}

/// `minimize pane "<id>" to "leading"`, and `to "none"` to restore.
///
/// Returns where the pane actually ended up, which is not always where the
/// script asked: a pane whose split has no such edge is refused by its host,
/// and the honest answer to "did that work" is the pane's own state.
@objc(MinimizePaneCommand)
public final class MinimizePaneCommand: MainActorScriptCommand, @unchecked Sendable {

    public override func performMain() -> Any? {
        let identifier = self.directParameter as? String
        guard let identifier,
              let pane = ProjectWindowManager.shared.scriptablePane(uniqueID: identifier) else {
            self.reportNoSuchPane(id: identifier)
            return "no"
        }
        // `to` is required by the `.sdef`, so AppleScript will not compile
        // `minimize pane X` without it and this fallback is unreachable from a
        // compiled script. It is for an Apple event assembled by hand that
        // omits the parameter or sends something that is not a string — and
        // restoring is the safe reading of a request that named no edge, since
        // the alternative is picking a side on the script's behalf.
        let edge = (self.evaluatedArguments?["Edge"] as? String) ?? "none"
        pane.minimizePane(to: edge)
        return pane.paneMinimized
    }
}
