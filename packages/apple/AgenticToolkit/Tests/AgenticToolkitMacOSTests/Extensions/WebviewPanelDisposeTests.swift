import Testing
import WebKit
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// What a panel does once it has been torn down, and how many times it will
/// say so.
///
/// Disposal has two owners and they do not know about each other:
/// `onDidDispose` belongs to the extension host, which forwards it to the
/// extension's own `onDidDispose`, and `onRemovalRequested` belongs to
/// whoever put the pane in a window. Both have to fire, and both have to fire
/// exactly once, because the two paths into here race by design — the user
/// closes the pane while the extension is disposing the panel it owns.
///
/// Until now the only double-dispose assertion in this bundle ran against
/// `MainThreadWebviewsTests`' own `TestWebviewPanel`, whose `dispose()` carries
/// a `guard disposeCount == 0` of its own. That test proves the fake is
/// idempotent. Nothing proved this class was.
///
/// No `loadView()` anywhere here, for the reason `WebviewPanelScriptPolicyTests`
/// gives at more length: a real `WKWebView` puts a web content process and a
/// navigation on the other side of every assertion. Nothing is lost — the
/// `webView?` lines in `dispose()` sit *after* the guard, so a second dispose
/// never reaches WebKit whether a view was loaded or not.
@MainActor
struct WebviewPanelDisposeTests {

    private func makePanel() -> WebviewPanelViewController {
        WebviewPanelViewController(
            viewType: "test.panel",
            title: "Panel",
            options: WebviewPanelOptions(
                enableScripts: true, enableForms: nil, localResourceRoots: nil),
            localResourceRoots: [])
    }

    /// Both owners hear, and the panel says it is gone. The second half
    /// matters on its own: `isDisposed` is what every other method here
    /// consults, so a `dispose()` that announced without recording would leave
    /// a panel that talks to a page it has released.
    @Test("disposing tells both owners once and records it")
    func disposeAnnouncesOnceToBothOwners() {
        let panel = makePanel()
        var disposals = 0
        var removals = 0
        panel.onDidDispose = { disposals += 1 }
        panel.onRemovalRequested = { removals += 1 }

        panel.dispose()

        #expect(panel.isDisposed)
        #expect(disposals == 1)
        #expect(removals == 1)
    }

    /// The ordinary race, in its simplest shape. An extension that disposes a
    /// panel the user already closed must not make the host forward a second
    /// `onDidDispose` to the extension, and must not ask the window to remove
    /// a pane that is no longer in its tree *(idempotency)*.
    @Test("a second dispose tells nobody anything")
    func aSecondDisposeAnnouncesNothing() {
        let panel = makePanel()
        var disposals = 0
        var removals = 0
        panel.onDidDispose = { disposals += 1 }
        panel.onRemovalRequested = { removals += 1 }

        panel.dispose()
        panel.dispose()
        panel.dispose()

        #expect(panel.isDisposed)
        #expect(disposals == 1)
        #expect(removals == 1)
    }

    /// The race as it actually arrives, which the two above do not reach.
    ///
    /// `onDidDispose` is the host's, and the host forwards it to the
    /// extension, and what an extension commonly does in its own
    /// `onDidDispose` is call `panel.dispose()` — tidying up something it
    /// believes it still owns. That call re-enters this method from inside its
    /// own callback. `isDisposed` is set *before* the callbacks run rather
    /// than after for exactly this reason: set it after, and the guard is
    /// still false when the extension calls back in, and the panel disposes
    /// itself forever.
    ///
    /// The re-entrant call is fired once rather than unconditionally so this
    /// test *fails* rather than exhausting the stack when the ordering is
    /// wrong.
    @Test("disposing from inside the dispose callback does not dispose twice")
    func aReentrantDisposeIsRefusedLikeAnyOther() {
        let panel = makePanel()
        var disposals = 0
        var removals = 0
        var hasReentered = false
        panel.onDidDispose = { [weak panel] in
            disposals += 1
            guard !hasReentered else { return }
            hasReentered = true
            panel?.dispose()
        }
        panel.onRemovalRequested = { removals += 1 }

        panel.dispose()

        #expect(hasReentered, "the test never exercised the re-entrant path")
        #expect(disposals == 1)
        #expect(removals == 1)
    }

    /// The user's path. Closing the pane is what runs this, and it has to
    /// reach the extension: an extension whose panel vanished and was never
    /// told holds a handle to a dead page and keeps posting to it.
    @Test("closing the pane disposes the panel")
    func closingThePaneDisposes() {
        let panel = makePanel()
        var disposals = 0
        panel.onDidDispose = { disposals += 1 }

        panel.paneContentWillBeDiscarded()

        #expect(panel.isDisposed)
        #expect(disposals == 1)
    }

    /// And the two paths crossing, which is the whole reason the guard is
    /// there: the pane closes, the extension answers by disposing.
    @Test("a pane close after an extension dispose announces nothing new")
    func closingAnAlreadyDisposedPaneIsQuiet() {
        let panel = makePanel()
        var disposals = 0
        var removals = 0
        panel.onDidDispose = { disposals += 1 }
        panel.onRemovalRequested = { removals += 1 }

        panel.dispose()
        panel.paneContentWillBeDiscarded()

        #expect(disposals == 1)
        #expect(removals == 1)
    }

    // MARK: - What a disposed panel refuses

    /// The control for the two below. A guard that refused everything would
    /// pass them both, and `reveal` is the one verb here whose failure is
    /// invisible — nothing happens, which is also what success looks like from
    /// the extension's side.
    @Test("revealing a live panel passes preserveFocus through")
    func revealCarriesPreserveFocus() {
        let panel = makePanel()
        var revealed: [Bool] = []
        panel.onRevealRequested = { revealed.append($0) }

        panel.reveal(preserveFocus: true)
        panel.reveal(preserveFocus: false)

        #expect(revealed == [true, false])
    }

    /// An extension holding a panel the user closed calls `reveal()` on it —
    /// which, unguarded, asks a presenter to select a pane that is no longer
    /// in any window's tree.
    @Test("revealing a disposed panel asks nobody for anything")
    func revealAfterDisposeIsIgnored() {
        let panel = makePanel()
        var reveals = 0
        panel.onRevealRequested = { _ in reveals += 1 }

        panel.dispose()
        panel.reveal(preserveFocus: false)

        #expect(reveals == 0)
    }

    /// A message already in flight when the panel went away. WebKit delivers
    /// what the page sent before the navigation was torn down, and the
    /// extension's handler is the one thing here that runs arbitrary code — so
    /// this is the difference between a dropped message and an extension being
    /// called back after it was told its panel no longer exists.
    @Test("a page message that arrives after dispose is dropped")
    func aPageMessageAfterDisposeIsDropped() {
        let panel = makePanel()
        var received: [Any] = []
        panel.onDidReceiveMessage = { received.append($0) }

        panel.webviewDidSend(kind: .postMessage, body: ["before": 1])
        panel.dispose()
        panel.webviewDidSend(kind: .postMessage, body: ["after": 2])

        #expect(received.count == 1)
    }

    /// The same race with worse consequences. `setState` is written down by
    /// the serializer, so a state message accepted during teardown overwrites
    /// what the panel will come back as next launch — with whatever the page
    /// happened to be saying as it was destroyed.
    @Test("a setState that arrives after dispose leaves the stored state alone")
    func aSetStateAfterDisposeIsDropped() {
        let panel = makePanel()
        panel.webviewDidSend(kind: .setState, body: ["scrollTop": 420])

        var announcements = 0
        panel.onRestorationStateChanged = { announcements += 1 }
        panel.dispose()
        panel.webviewDidSend(kind: .setState, body: ["scrollTop": 0])

        #expect(panel.state == #"{"scrollTop":420}"#)
        #expect(announcements == 0)
    }

    /// Disposal releases the page, not the record of it. The serializer reads
    /// `restorationState` *after* the pane is gone — that is the only moment
    /// it can, on the quit path — so a `dispose()` that cleared the title or
    /// the state would silently make every panel come back blank.
    @Test("restoration state survives disposal intact")
    func restorationStateSurvivesDispose() {
        let panel = makePanel()
        panel.title = "Preview: README.md"
        panel.webviewDidSend(kind: .setState, body: ["scrollTop": 420])

        panel.dispose()

        let restored = panel.restorationState
        #expect(restored.viewType == "test.panel")
        #expect(restored.title == "Preview: README.md")
        #expect(restored.state == #"{"scrollTop":420}"#)
        #expect(restored.options.enableScripts == true)
    }
}
