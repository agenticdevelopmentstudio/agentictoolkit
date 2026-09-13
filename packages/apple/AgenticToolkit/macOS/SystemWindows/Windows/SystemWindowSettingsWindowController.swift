import AppKit
import SwiftUI
import AgenticToolkitCoreMacOS

/// Manages a standalone window that hosts ``SystemWindowSettingsView`` — the
/// composite contexts / visualization / heuristics / shortcuts / general
/// settings surface.
///
/// SwiftUI hosts embed ``SystemWindowSettingsView`` directly in a `Settings`
/// scene; AppKit hosts (which have no `Settings` scene) use this controller
/// instead. Built on ``SingleWindowController`` so frame persistence flows
/// through `WindowManager` rather than bespoke bookkeeping.
@MainActor
public final class SystemWindowSettingsWindowController: SingleWindowController {

    public static let windowID = "systemwindow.settings"

    public init(model: SystemWindowContextsModel) {
        let root = SystemWindowSettingsView()
            .environmentObject(model)
            .themedRoot()
        super.init(
            windowID: Self.windowID,
            contentViewController: NSHostingController(rootView: root)
        )
        self.windowSpec = WindowSpec(
            defaultSize: NSSize(width: 580, height: 560),
            minSize: NSSize(width: 480, height: 400),
            defaultPosition: .center,
            behavior: .persistsFrame
        )
        self.windowTitle = "\(model.contextNounPlural) Settings"
        self.windowStyleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Single source of truth for the minimum size: track the spec rather than
        // repeating the literal.
        self.minSize = self.windowSpec?.minSize
    }

    public override func showWindow() {
        super.showWindow()
        // Bring the app forward so the settings window takes focus from a
        // menu-bar accessory host.
        NSApp.activateUnlessQuiet()
    }
}
