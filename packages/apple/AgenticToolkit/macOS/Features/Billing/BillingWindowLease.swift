import AppKit
import AgenticToolkitCore

/// Ties a billing window's controller to its window. While the window is on
/// screen the controller counts as one of `BillingModel`'s consumers, so the
/// model polls the lists. When it closes, the model stops counting it and
/// `onClose` runs, and the controller lets go of itself (its `current`).
/// Without that, a closed window would stay in memory and be rebuilt on
/// every poll for the rest of the session.
@MainActor
public final class BillingWindowLease {

    private let model: BillingModel
    private let onClose: @MainActor () -> Void
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    public init(model: BillingModel, windowController: NSWindowController, onClose: @escaping @MainActor () -> Void) {
        self.model = model
        self.onClose = onClose
        model.addConsumer(self) { [weak windowController] in
            windowController?.window?.isVisible == true
        }
        // Filtered by the window's controller rather than the window itself,
        // which the controller builds lazily and may not have yet.
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self, weak windowController] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard let self, let windowController, window.windowController === windowController else { return }
                self.windowClosed()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// The window was just shown: the lists are read now if they are stale.
    public func shown() {
        model.consumerShown()
    }

    private func windowClosed() {
        // Quitting closes every window; there is nothing to let go of then.
        guard !WindowManager.shared.isTerminating else { return }
        model.removeConsumer(self)
        // After the close finishes: the controller may be what owns the window.
        let onClose = self.onClose
        DispatchQueue.main.async { MainActor.assumeIsolated { onClose() } }
    }
}
