import AppKit
import SwiftUI
import AgenticToolkitCoreMacOS

/// A floating, non-activating panel that hosts the ``ContextPickerView`` for
/// fast context switching via a global keyboard shortcut.
///
/// Using `NSPanel` (rather than a SwiftUI `Window`) gives the picker the
/// semantics it needs:
/// - key-window behavior without forcing the app to activate
/// - automatic dismiss on focus loss (`hidesOnDeactivate`)
/// - borderless, floating, non-activating chrome
///
/// On dismiss (Escape or focus loss) the panel posts
/// ``Foundation/NSNotification/Name/contextPickerDismissed`` so the host can
/// clear its presentation flag.
public final class SystemWindowContextPickerPanel: NSPanel {

    /// The hosting view for the SwiftUI content.
    private var hostingView: NSHostingView<AnyView>?

    public init(model: SystemWindowContextsModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 340),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        let pickerView = ContextPickerView()
            .environmentObject(model)
            // The picker paints its own translucent `.ultraThinMaterial`
            // background over this borderless panel; skip the themed opaque
            // backdrop so the floating-panel blur isn't covered up.
            .themedRoot(paintsBackground: false)

        let hosting = NSHostingView(rootView: AnyView(pickerView))
        hosting.frame = contentRect(forFrameRect: frame)
        self.contentView = hosting
        self.hostingView = hosting
    }

    /// Shows the panel centered on the main screen, raised slightly above the
    /// vertical midpoint so it sits in the user's natural line of sight.
    public func showCentered() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = frame.size
        let originX = screenFrame.midX - panelSize.width / 2
        let originY = screenFrame.midY - panelSize.height / 2 + screenFrame.height * 0.15

        setFrame(NSRect(x: originX, y: originY, width: panelSize.width, height: panelSize.height), display: true)
        makeKeyAndOrderFront(nil)

        // Bring the app temporarily to the foreground so the panel can receive
        // key events even when the host runs as a menu-bar accessory.
        NSApp.activateUnlessQuiet()
    }

    public override var canBecomeKey: Bool { true }

    /// Installs a NotificationCenter observer that clears `model.showContextPicker`
    /// when the panel self-dismisses (Escape / focus loss), so each host doesn't
    /// re-implement the same bridge. The caller retains the returned token and
    /// removes it when finished (e.g. in `deinit`).
    @MainActor
    public static func observeDismissal(
        updating model: SystemWindowContextsModel
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .contextPickerDismissed,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            Task { @MainActor in model?.showContextPicker = false }
        }
    }

    public override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .contextPickerDismissed, object: nil)
        }
    }

    public override func resignKey() {
        super.resignKey()
        orderOut(nil)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .contextPickerDismissed, object: nil)
        }
    }
}
