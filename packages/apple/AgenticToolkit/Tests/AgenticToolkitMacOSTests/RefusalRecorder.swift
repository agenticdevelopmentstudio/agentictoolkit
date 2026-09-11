import XCTest
@testable import AgenticToolkitMacOS

/// Counts the framework's refusals instead of beeping them.
///
/// Several tests drive a refused close on purpose, and until `RefusalFeedback`
/// existed every one of them reached the speaker of whoever was at the
/// keyboard — four beeps per run, with nothing saying which test had done it.
///
/// It is not only a mute. A refusal that is announced and one that is silently
/// ignored leave the tree in exactly the same state, so `allLeaves()` cannot
/// tell them apart and the count is the only evidence the `guard` said
/// anything at all. Announcing is the whole point of that `guard`: a pane whose
/// close button does nothing and says nothing reads as broken rather than
/// protected.
@MainActor
final class RefusalRecorder {

    private(set) var count = 0

    fileprivate func record() { count += 1 }
}

extension XCTestCase {

    /// Routes `RefusalFeedback` into a recorder for the rest of this test, and
    /// puts the previous announcer back afterwards.
    ///
    /// Restoring rather than assuming the default: the seam is a shared static,
    /// so a test that left its own closure installed would silently change what
    /// every later test in the process observed.
    @MainActor
    func recordingRefusals() -> RefusalRecorder {
        let recorder = RefusalRecorder()
        let previous = RefusalFeedback.announce
        RefusalFeedback.announce = { recorder.record() }
        addTeardownBlock { @MainActor in RefusalFeedback.announce = previous }
        return recorder
    }
}
