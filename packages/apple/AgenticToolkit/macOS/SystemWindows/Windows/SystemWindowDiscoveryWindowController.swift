import AppKit
import SwiftUI
import AgenticToolkitCoreMacOS

/// Manages the window that hosts ``DiscoveryView`` — the "discover windows"
/// surface that lists every running window grouped by app and lets the user
/// batch-add them to a context.
///
/// Built on ``SingleWindowController`` so frame persistence flows through
/// `WindowManager` (proportional, screen-aware) instead of bespoke
/// `UserDefaults` bookkeeping. On show it posts
/// ``Foundation/NSNotification/Name/discoveryPanelShown`` so the explorer
/// refreshes its running-window snapshot.
@MainActor
public final class SystemWindowDiscoveryWindowController: SingleWindowController {

    public static let windowID = "systemwindow.discovery"

    public init(model: SystemWindowContextsModel) {
        let root = DiscoveryView()
            .environmentObject(model)
            .themedRoot()
        super.init(
            windowID: Self.windowID,
            contentViewController: NSHostingController(rootView: root)
        )
        self.windowSpec = WindowSpec(
            defaultSize: NSSize(width: 560, height: 520),
            minSize: NSSize(width: 420, height: 320),
            defaultPosition: .center,
            behavior: .persistsFrame
        )
        self.windowTitle = "Discover Windows"
        self.windowStyleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Single source of truth for the minimum size: track the spec rather than
        // repeating the literal.
        self.minSize = self.windowSpec?.minSize
    }

    public override func showWindow() {
        super.showWindow()
        // Bring the app forward so the window takes focus from a menu-bar
        // accessory host.
        NSApp.activateUnlessQuiet()
        // Let the window settle before the explorer enumerates windows, so the
        // discovery window itself isn't captured in the snapshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .discoveryPanelShown, object: nil)
        }
    }
}
