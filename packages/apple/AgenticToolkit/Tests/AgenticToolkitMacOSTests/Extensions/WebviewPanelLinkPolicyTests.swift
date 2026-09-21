import Foundation
import Testing
import WebKit
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Where a navigation inside an extension's panel is allowed to go.
///
/// Opening `https://` links in the user's browser is the intended behaviour and
/// what VS Code does — the panel is not a browser, and a link that silently did
/// nothing would be a worse bug than this one. What is *not* intended is the
/// rate: `.linkActivated` is the type WebKit reports for `anchor.click()` as
/// well as for a real click, so a page that calls it in a loop was asking the
/// window server for a browser window per iteration. The user does not get a
/// prompt, a permission or a way to stop it; they get hundreds of tabs.
@MainActor
struct WebviewPanelLinkPolicyTests {

    /// `WKNavigationAction` has no initialiser to call and no way to set what a
    /// test needs to vary, so the two properties the policy reads are
    /// overridden. Nothing else about it is touched.
    private final class FakeNavigationAction: WKNavigationAction {
        private let url: URL?
        private let type: WKNavigationType

        init(_ url: URL?, type: WKNavigationType = .linkActivated) {
            self.url = url
            self.type = type
            super.init()
        }

        override var request: URLRequest {
            guard let url else { return URLRequest(url: URL(string: "about:blank")!) }
            return URLRequest(url: url)
        }

        override var navigationType: WKNavigationType { type }
    }

    private func makePanel(
        opening opened: @escaping (URL) -> Void
    ) -> WebviewPanelViewController {
        let panel = WebviewPanelViewController(
            viewType: "test.panel",
            title: "Panel",
            options: WebviewPanelOptions(
                enableScripts: true, enableForms: nil, localResourceRoots: nil),
            localResourceRoots: [])
        panel.openExternalURL = opened
        return panel
    }

    @Test("a clicked link goes to the browser and the page stays where it is")
    func aClickedLinkOpensExternally() {
        var opened: [URL] = []
        let panel = makePanel { opened.append($0) }
        let link = URL(string: "https://example.com/docs")!

        let decision = panel.policy(for: FakeNavigationAction(link))

        #expect(decision == .cancel)
        #expect(opened == [link])
    }

    /// The bug. Fifty activations in a tight loop is a page's whole cost;
    /// fifty browser windows is the user's.
    @Test("a burst of link activations opens the browser once")
    func aBurstOpensTheBrowserOnce() {
        var opened: [URL] = []
        let panel = makePanel { opened.append($0) }

        for index in 0..<50 {
            _ = panel.policy(for: FakeNavigationAction(
                URL(string: "https://example.com/\(index)")!))
        }

        #expect(opened.count == 1)
        #expect(opened.first == URL(string: "https://example.com/0")!)
    }

    /// And the converse, which is what stops the fix from being a latch that
    /// permanently breaks links after the first one: with the interval elapsed,
    /// every activation is honoured again. A user reading documentation clicks
    /// more than one link in a session.
    @Test("links open again once the interval has passed")
    func theThrottleIsNotALatch() {
        var opened: [URL] = []
        let panel = makePanel { opened.append($0) }
        panel.externalOpenInterval = 0

        for index in 0..<5 {
            _ = panel.policy(for: FakeNavigationAction(
                URL(string: "https://example.com/\(index)")!))
        }

        #expect(opened.count == 5)
    }

    /// Not every navigation is a link. A page that assigns `location.href`
    /// reports `.other`, and that is a page trying to leave on its own rather
    /// than a user asking to — it is cancelled, and nothing is opened.
    @Test("a scripted navigation is cancelled without opening anything")
    func aScriptedNavigationOpensNothing() {
        var opened: [URL] = []
        let panel = makePanel { opened.append($0) }

        let decision = panel.policy(for: FakeNavigationAction(
            URL(string: "https://example.com/")!, type: .other))

        #expect(decision == .cancel)
        #expect(opened.isEmpty)
    }

    /// The panel's own document is the one thing that may load, and the
    /// throttle must not be in its way — it is not an external open at all.
    @Test("the panel's own document is allowed")
    func theHostDocumentIsAllowed() {
        var opened: [URL] = []
        let panel = makePanel { opened.append($0) }
        let host = WebviewResourceURL.hostDocumentURL(panelID: panel.panelID)

        let decision = panel.policy(for: FakeNavigationAction(host, type: .other))

        #expect(decision == .allow)
        #expect(opened.isEmpty)
    }
}
