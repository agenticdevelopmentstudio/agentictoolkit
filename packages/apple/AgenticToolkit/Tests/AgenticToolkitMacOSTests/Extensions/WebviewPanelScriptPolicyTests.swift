import Testing
import WebKit
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Whether a panel's page may run JavaScript.
///
/// The one option here that is a security boundary rather than a preference: a
/// webview that runs scripts can talk to the host over the message handler,
/// and `enableScripts` is how an extension says whether its page needs that.
/// Off unless asked for, so getting it wrong in the "on" direction is the
/// failure that matters.
///
/// Asserted against the preferences object the navigation delegate hands back,
/// not against a loaded page. That is the same choice `MainThreadWebviewsTests`
/// explains at more length — a real `WKWebView` puts a web content process and
/// a navigation on the other side of every assertion — and it is the whole of
/// what the delegate decides: WebKit consults these preferences when a
/// navigation commits, and nothing else in this class has a say.
@MainActor
struct WebviewPanelScriptPolicyTests {

    private func makeController(enableScripts: Bool?) -> WebviewPanelViewController {
        WebviewPanelViewController(
            viewType: "test.panel",
            title: "Panel",
            options: WebviewPanelOptions(
                enableScripts: enableScripts, enableForms: nil, localResourceRoots: nil),
            localResourceRoots: [])
    }

    private func options(enableScripts: Bool) -> WebviewPanelOptions {
        WebviewPanelOptions(
            enableScripts: enableScripts, enableForms: nil, localResourceRoots: nil)
    }

    /// The default, and the one that has to hold: an extension that said
    /// nothing about scripts gets a page that cannot run them.
    @Test("a panel that did not ask for scripts refuses them")
    func scriptsAreOffUnlessAskedFor() {
        let controller = makeController(enableScripts: nil)
        #expect(controller.navigationPreferences().allowsContentJavaScript == false)
    }

    @Test("a panel that asked for scripts gets them")
    func scriptsAreOnWhenAskedFor() {
        let controller = makeController(enableScripts: true)
        #expect(controller.navigationPreferences().allowsContentJavaScript == true)
    }

    /// `webview.options = { enableScripts: false }` on a panel that had them.
    ///
    /// This is the case that was silently failing open. The setter wrote to
    /// `webView.configuration`, which is `@NSCopying` — the getter hands back a
    /// copy, so the write landed on a throwaway and the live page kept running
    /// scripts. Nothing observed it, because the only thing that reads the
    /// value back is WebKit.
    @Test("taking scripts away afterwards is carried by the next navigation")
    func scriptsCanBeTakenAway() {
        let controller = makeController(enableScripts: true)
        controller.options = options(enableScripts: false)
        #expect(controller.navigationPreferences().allowsContentJavaScript == false)
    }

    @Test("granting scripts afterwards is carried too")
    func scriptsCanBeGranted() {
        let controller = makeController(enableScripts: false)
        controller.options = options(enableScripts: true)
        #expect(controller.navigationPreferences().allowsContentJavaScript == true)
    }

    /// Each navigation is asked separately, so the answer may not be a value
    /// computed once and cached — a panel restored from disk and a panel whose
    /// options changed have to get the current answer, not the first one.
    @Test("the answer is recomputed per navigation, not captured once")
    func theAnswerFollowsTheCurrentOptions() {
        let controller = makeController(enableScripts: false)
        let first = controller.navigationPreferences()
        controller.options = options(enableScripts: true)
        let second = controller.navigationPreferences()
        #expect(first.allowsContentJavaScript == false)
        #expect(second.allowsContentJavaScript == true)
    }
}
