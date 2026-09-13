import AppKit

/// Tracks every live `SingleWindowController` by its `windowID` so callers
/// (scripting commands, debug tools) can look one up without holding a
/// reference. Entries hold weak refs — a dropped controller naturally
/// disappears from `controller(forID:)` lookups.
///
/// Owned by `WindowManager`; populated automatically by
/// `SingleWindowController.init(windowID:contentViewController:)`.
@MainActor
public final class WindowRegistry {

    private struct WeakBox {
        weak var controller: SingleWindowController?
    }

    private var entries: [String: WeakBox] = [:]

    public init() {}

    /// Registers the controller under its own `windowID`. Re-registering the
    /// same `windowID` replaces the prior entry — the assumption is one live
    /// controller per ID.
    public func register(_ controller: SingleWindowController) {
        guard !controller.windowID.isEmpty else { return }
        entries[controller.windowID] = WeakBox(controller: controller)
    }

    /// Returns the live controller for `id`, or `nil` if none is registered
    /// or the previously-registered one has been deallocated.
    public func controller(forID id: String) -> SingleWindowController? {
        entries[id]?.controller
    }

    /// IDs of every currently-live registered controller — which is not the
    /// same as every window that is *open*. A controller outlives the window it
    /// shows: closing a window leaves its controller registered so the next
    /// `show()` reuses it. Use `visibleIDs` to ask what is on screen.
    public var registeredIDs: [String] {
        entries.compactMap { $0.value.controller != nil ? $0.key : nil }
    }

    /// IDs of the registered controllers whose window is on screen right now.
    ///
    /// What a script asking "which windows are open?" means, and what a
    /// debugging read of the app's state is almost always after.
    public var visibleIDs: [String] {
        entries.compactMap { isVisible($0.value) ? $0.key : nil }
    }

    /// Whether any registered controller currently has its window on screen.
    ///
    /// A host's launch path asks this before activating the app: restoring
    /// windows is what a person launching the app wants brought to the front,
    /// and a launch that restored nothing — a menubar app starting at login
    /// with every window closed last session — has nothing to take the
    /// foreground for.
    public var hasVisibleWindow: Bool {
        entries.values.contains(where: isVisible)
    }

    /// One definition of "on screen", so the two readers above cannot answer
    /// the same question differently (`dry`).
    private func isVisible(_ box: WeakBox) -> Bool {
        box.controller?.isVisible == true
    }
}
