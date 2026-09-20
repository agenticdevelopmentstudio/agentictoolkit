import Testing
import WebKit
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// What a panel remembers of its page, and what it is allowed to forget.
///
/// `setState` is the one thing a webview can say that outlives a quit: the
/// serializer writes `restorationState` down every time this changes, and hands
/// it back to the extension on the next launch. So the interesting cases are
/// not the ones that store a value — they are the ones that *don't*, because a
/// panel that answers a bad message by erasing the good answer loses work the
/// page believed was saved.
@MainActor
struct WebviewPanelStateTests {

    private func makePanel() -> WebviewPanelViewController {
        WebviewPanelViewController(
            viewType: "test.panel",
            title: "Panel",
            options: WebviewPanelOptions(
                enableScripts: true, enableForms: nil, localResourceRoots: nil),
            localResourceRoots: [])
    }

    @Test("a page's state is stored as JSON text and announced")
    func setStateIsStoredAndAnnounced() {
        let panel = makePanel()
        var announcements = 0
        panel.onRestorationStateChanged = { announcements += 1 }

        panel.webviewDidSend(kind: .setState, body: ["scrollTop": 420])

        #expect(panel.state == #"{"scrollTop":420}"#)
        #expect(panel.restorationState.state == #"{"scrollTop":420}"#)
        #expect(announcements == 1)
    }

    /// The bug this pins. `new Date()` is a value WebKit hands over as an
    /// `NSDate`, which `JSONSerialization` will not encode — so the encode
    /// fails, and the log says the value was dropped. It was not only the value
    /// that got dropped: the failure answered `nil`, `nil` was assigned to the
    /// stored state, and the announcement wrote that erasure into the project.
    /// A page that had saved its scroll position an hour ago and then said one
    /// thing this host cannot encode came back blank.
    ///
    /// Dropping the *message* is the right answer; the last state that could be
    /// encoded is what the panel still has to come back as.
    @Test("a state this host cannot encode leaves the last good one alone")
    func anUnencodableStateKeepsThePreviousOne() {
        let panel = makePanel()
        panel.webviewDidSend(kind: .setState, body: ["scrollTop": 420])

        var announcements = 0
        panel.onRestorationStateChanged = { announcements += 1 }
        panel.webviewDidSend(kind: .setState, body: Date())

        #expect(panel.state == #"{"scrollTop":420}"#)
        #expect(announcements == 0)
    }

    /// And the same when there was nothing to keep: nothing is stored, and
    /// nothing is announced, so a panel that has never had a state does not get
    /// a write of `nil` on the strength of a message that failed.
    @Test("a first state that cannot be encoded stores nothing and says nothing")
    func anUnencodableFirstStateIsSilent() {
        let panel = makePanel()
        var announcements = 0
        panel.onRestorationStateChanged = { announcements += 1 }

        panel.webviewDidSend(kind: .setState, body: Date())

        #expect(panel.state == nil)
        #expect(announcements == 0)
    }

    /// The unencodable value is rarely the whole message — `{ scrollTop: 12,
    /// openedAt: new Date() }` is an ordinary thing for a page to save, and
    /// `NaN` gets in the same way. The check has to be the recursive one, or
    /// the top level looks like a perfectly good dictionary right up until the
    /// encoder reaches the element that takes the app down.
    @Test("an unencodable value nested in a good object is caught too")
    func anUnencodableNestedValueIsCaught() {
        let panel = makePanel()
        panel.webviewDidSend(kind: .setState, body: ["scrollTop": 420])

        panel.webviewDidSend(kind: .setState, body: ["scrollTop": 12, "openedAt": Date()])
        panel.webviewDidSend(kind: .setState, body: ["ratio": Double.nan])

        #expect(panel.state == #"{"scrollTop":420}"#)
    }

    /// `setState(null)` is a page deliberately clearing its state, and it must
    /// still reach storage — which is why the encode allows fragments. This is
    /// the case that stops "keep the last good one" from being implemented as
    /// "ignore anything falsy".
    @Test("a page that clears its state is obeyed")
    func clearingStateIsStored() {
        let panel = makePanel()
        panel.webviewDidSend(kind: .setState, body: ["scrollTop": 420])

        var announcements = 0
        panel.onRestorationStateChanged = { announcements += 1 }
        panel.webviewDidSend(kind: .setState, body: NSNull())

        #expect(panel.state == "null")
        #expect(announcements == 1)
    }
}
