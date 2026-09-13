import AppKit
import Combine
import SwiftUI
import AgenticToolkitCoreMacOS

/// Manages the window that hosts ``ReconcileView`` — the surface that prompts the
/// user to re-attach previously tracked windows that couldn't be auto-matched on
/// launch.
///
/// Unlike the discovery and settings windows (shown from a menu action),
/// reconcile is driven by the model: `performLaunchReconciliation()` sets
/// `showReconcileWindow` when unmatched windows remain. This controller observes
/// that flag and presents (or hides) itself, so any host that simply creates and
/// retains it gets the reconcile prompt with no extra wiring — a SwiftUI host does
/// the same with `.onChange(of:)`. Built on ``SingleWindowController`` so frame
/// persistence flows through `WindowManager`.
@MainActor
public final class SystemWindowReconcileWindowController: SingleWindowController {

    public static let windowID = "systemwindow.reconcile"

    private let model: SystemWindowContextsModel
    private var cancellables = Set<AnyCancellable>()

    public init(model: SystemWindowContextsModel) {
        self.model = model
        let root = ReconcileView()
            .environmentObject(model)
            .themedRoot()
        super.init(
            windowID: Self.windowID,
            contentViewController: NSHostingController(rootView: root)
        )
        self.windowSpec = WindowSpec(
            defaultSize: NSSize(width: 600, height: 500),
            minSize: NSSize(width: 480, height: 360),
            defaultPosition: .center,
            behavior: .persistsFrame
        )
        self.windowTitle = "Reconcile Windows"
        self.windowStyleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Single source of truth for the minimum size: track the spec.
        self.minSize = self.windowSpec?.minSize

        observeReconcileFlag()
    }

    /// Presents the window when the model asks for reconciliation and hides it
    /// when the model clears the flag (the "Dismiss" button), so the host doesn't
    /// have to bridge the flag itself.
    private func observeReconcileFlag() {
        model.$showReconcileWindow
            .receive(on: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] shouldShow in
                guard let self else { return }
                if shouldShow {
                    self.showWindow()
                } else if self.isWindowLoaded {
                    // Guard on `isWindowLoaded` so the initial `false` emission
                    // doesn't force the window to load before it's ever shown.
                    self.window?.orderOut(nil)
                }
            }
            .store(in: &cancellables)
    }

    public override func showWindow() {
        super.showWindow()
        // Bring the app forward so the prompt takes focus from a menu-bar
        // accessory host.
        NSApp.activateUnlessQuiet()
    }
}
