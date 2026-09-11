import AppKit

/// How the framework says "no" to an action it will not perform.
///
/// Ten places answered a refusal by calling `NSSound.beep()` directly — a pane
/// refusing to close, arrange mode refusing a move or a removal or an empty
/// add menu, the file browser with no selected root, the theme and AI settings
/// panels with nothing selected. Calling the speaker from the decision point
/// made the refusal both unassertable and unmutable: four tests drive a refused
/// close on purpose, and every one of them beeped at whoever was at the
/// keyboard, with nothing in the run saying which test had done it.
///
/// One seam instead, in the same shape as
/// `NotesSplitViewController.storageFailurePresenter`. Production behaviour is
/// unchanged — the default still beeps, at the same moments — and a test
/// replaces `announce`, which lets it assert the refusal was *reported* rather
/// than only that nothing happened. That was the half those tests were missing:
/// a refusal that is silently ignored and a refusal that is announced look
/// identical from the outside, and the announcement is the whole point of the
/// `guard` (see `ComposableTabsViewController.paneDidRequestClose`).
@MainActor
public enum RefusalFeedback {

    /// Not a test-only switch. A host that wants a different signal — a shake,
    /// a status-bar message, silence — sets this too; the framework's job is to
    /// decide that the answer is no, not to own how that reaches a person.
    ///
    /// Replaced rather than wrapped: a caller that wants to keep the beep and
    /// add to it can capture the old value first.
    public static var announce: () -> Void = { NSSound.beep() }
}
