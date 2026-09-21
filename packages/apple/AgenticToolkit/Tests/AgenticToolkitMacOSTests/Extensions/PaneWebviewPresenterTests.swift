import Foundation
import Testing
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The wiring between a `createWebviewPanel` call and the pane it lands in.
///
/// Small surface, and every line of it is a fact that is invisible until a
/// user notices it is wrong: which verb was hooked to which callback, whether
/// the panel is revealed before or after it is wired, and whether a window
/// that cannot take a pane fails quietly or half-builds one.
///
/// Testable at all because `place` is already a closure — the pane tree is the
/// app's and never crosses into this framework. Nothing here needs a window,
/// a `ProjectWindowManager`, or a loaded view.
@MainActor
struct PaneWebviewPresenterTests {

    private func makeRequest(
        viewType: String = "acme.preview",
        title: String = "Preview",
        preserveFocus: Bool = false
    ) -> ExtensionWebviewPanelRequest {
        ExtensionWebviewPanelRequest(
            viewType: viewType,
            title: title,
            options: WebviewPanelOptions(
                enableScripts: true, enableForms: nil, localResourceRoots: nil),
            localResourceRoots: [],
            preserveFocus: preserveFocus,
            extensionIdentifier: "acme.widget")
    }

    /// Records what the app was asked to do, in order.
    @MainActor
    private final class Recorder {
        var placed: [WebviewPanelViewController] = []
        var revealed: [Bool] = []
        var removals = 0
    }

    // MARK: - The panel that is built

    /// The request's identity reaches the panel. `viewType` in particular is
    /// not decoration: it is the key a serializer is registered against, so a
    /// panel built under the wrong one is a panel that never restores.
    @Test("the panel is built from the request")
    func thePanelIsBuiltFromTheRequest() throws {
        let recorder = Recorder()
        let presenter = PaneWebviewPresenter { panel in
            recorder.placed.append(panel)
            return ExtensionWebviewPlacement(reveal: { _ in }, remove: { })
        }

        let returned = presenter.presentWebviewPanel(
            makeRequest(viewType: "acme.chart", title: "Chart"))

        let panel = try #require(returned as? WebviewPanelViewController)
        #expect(panel.viewType == "acme.chart")
        #expect(panel.panelTitle == "Chart")
        #expect(recorder.placed.count == 1)
        #expect(recorder.placed.first === panel)
    }

    /// The panel handed back is the one placed, not a second one built after
    /// placement — which would leave the app holding a view that receives no
    /// messages and cannot be disposed.
    @Test("the panel placed is the panel returned")
    func thePanelPlacedIsThePanelReturned() throws {
        let recorder = Recorder()
        let presenter = PaneWebviewPresenter { panel in
            recorder.placed.append(panel)
            return ExtensionWebviewPlacement(reveal: { _ in }, remove: { })
        }

        let first = try #require(
            presenter.presentWebviewPanel(makeRequest()) as? WebviewPanelViewController)
        let second = try #require(
            presenter.presentWebviewPanel(makeRequest()) as? WebviewPanelViewController)

        #expect(first !== second)
        #expect(first.panelID != second.panelID)
        #expect(recorder.placed.count == 2)
    }

    // MARK: - Nowhere to put it

    /// No project window open. `nil` is the contract `MainThreadWebviews`
    /// turns into a rejected `createWebviewPanel`, and anything else — a panel
    /// with no pane — is a webview the extension can post to forever with
    /// nobody watching.
    @Test("a placement that fails answers nil")
    func aPlacementThatFailsAnswersNil() {
        let presenter = PaneWebviewPresenter { _ in nil }

        #expect(presenter.presentWebviewPanel(makeRequest()) == nil)
    }

    /// And it is not revealed on the way out. `reveal` fires
    /// `onRevealRequested`, which is still `nil` at that point, so the visible
    /// damage of getting this wrong is zero today — until someone moves the
    /// reveal above the guard, at which point a failed placement starts
    /// selecting whatever pane the stale closure last knew about.
    @Test("a placement that fails reveals nothing")
    func aPlacementThatFailsRevealsNothing() {
        var revealCalls = 0
        let presenter = PaneWebviewPresenter { panel in
            panel.onRevealRequested = { _ in revealCalls += 1 }
            return nil
        }

        _ = presenter.presentWebviewPanel(makeRequest(preserveFocus: true))

        #expect(revealCalls == 0)
    }

    // MARK: - Which verb goes where

    /// The swap this whole `install` method exists to prevent. Both verbs take
    /// a closure, one of them ignores its argument, and the compiler is happy
    /// either way round — `reveal` wired to `onRemovalRequested` means the
    /// pane vanishes when the extension calls `panel.reveal()`.
    @Test("reveal is wired to reveal and removal to removal")
    func theTwoVerbsAreNotSwapped() throws {
        let recorder = Recorder()
        let presenter = PaneWebviewPresenter { _ in
            ExtensionWebviewPlacement(
                reveal: { recorder.revealed.append($0) },
                remove: { recorder.removals += 1 })
        }

        let panel = try #require(
            presenter.presentWebviewPanel(makeRequest()) as? WebviewPanelViewController)
        // One reveal has already happened: the create call's own.
        #expect(recorder.revealed == [false])
        #expect(recorder.removals == 0)

        panel.reveal(preserveFocus: true)
        #expect(recorder.revealed == [false, true])
        #expect(recorder.removals == 0)

        panel.dispose()
        #expect(recorder.revealed == [false, true])
        #expect(recorder.removals == 1)
    }

    /// `install` is a method on the placement rather than two assignments at
    /// each call site, so it gets an assertion of its own — the restore path
    /// uses it too, and there the mistake only shows after a relaunch.
    @Test("installing a placement hooks both callbacks")
    func installingAPlacementHooksBothCallbacks() {
        let recorder = Recorder()
        let panel = WebviewPanelViewController(
            viewType: "acme.preview",
            title: "Preview",
            options: WebviewPanelOptions(
                enableScripts: true, enableForms: nil, localResourceRoots: nil),
            localResourceRoots: [])
        #expect(panel.onRevealRequested == nil)
        #expect(panel.onRemovalRequested == nil)

        ExtensionWebviewPlacement(
            reveal: { recorder.revealed.append($0) },
            remove: { recorder.removals += 1 }
        ).install(on: panel)

        panel.reveal(preserveFocus: true)
        panel.dispose()

        #expect(recorder.revealed == [true])
        #expect(recorder.removals == 1)
    }

    // MARK: - preserveFocus

    /// `createWebviewPanel` creates *and* shows in one call, so the reveal is
    /// not optional — and `preserveFocus` is the only thing distinguishing a
    /// panel that takes the user's caret from one that does not.
    @Test("the create call reveals once, carrying preserveFocus")
    func theCreateCallRevealsOnceCarryingPreserveFocus() {
        for asked in [true, false] {
            let recorder = Recorder()
            let presenter = PaneWebviewPresenter { _ in
                ExtensionWebviewPlacement(
                    reveal: { recorder.revealed.append($0) }, remove: { })
            }

            _ = presenter.presentWebviewPanel(makeRequest(preserveFocus: asked))

            #expect(recorder.revealed == [asked], "preserveFocus: \(asked)")
        }
    }

    /// The ordering, stated as an assertion rather than as a comment. The
    /// reveal must come *after* the placement is installed, because it is the
    /// installed closure that performs it; revealing first is a call into a
    /// `nil` optional, which is silent.
    @Test("the panel is wired before it is revealed")
    func thePanelIsWiredBeforeItIsRevealed() {
        var revealsSeen = 0
        let presenter = PaneWebviewPresenter { panel in
            // A reveal landing here would mean the presenter revealed before
            // `install` replaced this closure.
            panel.onRevealRequested = { _ in
                Issue.record("revealed before the placement was installed")
            }
            return ExtensionWebviewPlacement(
                reveal: { _ in revealsSeen += 1 }, remove: { })
        }

        _ = presenter.presentWebviewPanel(makeRequest(preserveFocus: true))

        #expect(revealsSeen == 1)
    }

    // MARK: - Disposal

    /// The panel's own idempotence, seen from the app's side: the pane is
    /// asked to go away exactly once however many times disposal is reached.
    /// Both paths are real — the extension calling `panel.dispose()` and the
    /// user closing the pane, which arrives at the same method.
    @Test("a second dispose does not ask the app to remove the pane twice")
    func aSecondDisposeDoesNotRemoveTwice() throws {
        let recorder = Recorder()
        let presenter = PaneWebviewPresenter { _ in
            ExtensionWebviewPlacement(
                reveal: { _ in }, remove: { recorder.removals += 1 })
        }

        let panel = try #require(
            presenter.presentWebviewPanel(makeRequest()) as? WebviewPanelViewController)
        panel.dispose()
        panel.dispose()
        panel.paneContentWillBeDiscarded()

        #expect(recorder.removals == 1)
    }
}
