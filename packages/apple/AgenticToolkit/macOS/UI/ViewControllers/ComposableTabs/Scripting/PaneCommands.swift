import AppKit

/// `close pane "<id>"`.
///
/// The direct parameter is a pane id rather than a specifier, matching the
/// commands this app already has (`send message`, `new terminal session`).
/// A script that has a pane object has its id; a script that has only an id
/// does not have to build a specifier to use it.
@objc(ClosePaneCommand)
public final class ClosePaneCommand: MainActorScriptCommand, @unchecked Sendable {

    public override func performMain() -> Any? {
        guard let identifier = self.directParameter as? String,
              let pane = ProjectWindowManager.shared.scriptablePane(uniqueID: identifier) else {
            return false
        }
        pane.closePane()
        return true
    }
}

/// `zoom pane "<id>"` — returns the zoom state afterwards, so a script can
/// toggle and check in one step.
@objc(ZoomPaneCommand)
public final class ZoomPaneCommand: MainActorScriptCommand, @unchecked Sendable {

    public override func performMain() -> Any? {
        guard let identifier = self.directParameter as? String,
              let pane = ProjectWindowManager.shared.scriptablePane(uniqueID: identifier) else {
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
        guard let identifier = self.directParameter as? String,
              let pane = ProjectWindowManager.shared.scriptablePane(uniqueID: identifier) else {
            return "no"
        }
        let edge = (self.evaluatedArguments?["Edge"] as? String) ?? "none"
        pane.minimizePane(to: edge)
        return pane.paneMinimized
    }
}
