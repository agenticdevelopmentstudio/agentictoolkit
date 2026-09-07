import AppKit

/// What a window's chrome needs from whatever is showing help.
///
/// The chrome and the help button talk to this and never to `NSDrawer`, which
/// is what keeps a deprecated API confined to one wrapper instead of spreading
/// its warning across every file that mentions help. It also leaves the door
/// open for a host that would rather present help some other way — a panel, a
/// popover, a second window — without touching the chrome that asks for it.
@MainActor
public protocol HelpPresenting: AnyObject {

    /// The help for whatever is now showing; `nil` when it offers none.
    func setHelp(_ content: HelpContent?)

    /// Whether help is on screen right now.
    var isHelpVisible: Bool { get }

    /// Shows or hides help, remembering the choice if this presenter remembers.
    func toggleHelp()

    /// The help button now on screen. A presenter that attaches help to the
    /// window (a drawer) ignores it; one that hangs help off the control that
    /// asked for it (a popover) needs it, and only the chrome knows where that
    /// control ended up.
    var helpAnchorView: NSView? { get set }

    /// Called after `isHelpVisible` changes, so the chrome can restyle itself.
    /// The presenter can change on its own — a remembered preference is shared
    /// by every window using it — so the button can't assume its own click is
    /// the only thing that moves the drawer.
    var onVisibilityChange: (() -> Void)? { get set }
}
