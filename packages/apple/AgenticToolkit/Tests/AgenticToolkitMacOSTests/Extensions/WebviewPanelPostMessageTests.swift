import Foundation
import Testing
import WebKit
@testable import AgenticToolkitMacOS

/// What an extension is allowed to hand to `webview.postMessage(...)`.
///
/// `callAsyncJavaScript(arguments:)` documents the types it takes — `NSNumber`,
/// `NSNull`, `NSString`, `NSDate`, `NSArray`, `NSDictionary` — and answers
/// anything else with an Objective-C `NSInvalidArgumentException`. That is not
/// an error this host can catch: `try?` does not see it, and it takes the app
/// down. The value comes from `JSValue.toObject()` on whatever the extension
/// passed, so reaching the unsupported set needs no malice at all — a
/// `vscode.Uri` or any other native-backed object bridges straight to it.
///
/// So the rule is checked here rather than discovered there. These tests are
/// about the *boundary* of the accepted set, because a check that is too
/// strict drops messages upstream would have delivered and a check that is too
/// loose is the crash it was written to prevent.
struct WebviewPanelPostMessageTests {

    @Test("the ordinary shapes a page is sent are postable")
    func ordinaryValuesArePostable() {
        #expect(WebviewPanelViewController.isPostable(NSNull()))
        #expect(WebviewPanelViewController.isPostable("hello"))
        #expect(WebviewPanelViewController.isPostable(42))
        #expect(WebviewPanelViewController.isPostable(true))
        #expect(WebviewPanelViewController.isPostable([1, "two", NSNull()] as [Any]))
        #expect(WebviewPanelViewController.isPostable(
            ["command": "refresh", "items": [1, 2, 3], "done": false] as [String: Any]))
    }

    /// **The set is not the JSON set**, and this is the whole of the
    /// difference. `JSONSerialization` refuses a `Date` — which is why
    /// `setState` drops one — but `callAsyncJavaScript` takes it and the page
    /// receives a JavaScript `Date`. Checking postability with
    /// `isValidJSONObject` would therefore throw away `{ openedAt: new Date() }`,
    /// an ordinary message, to prevent a crash it does not cause.
    @Test("a date is postable even though it is not JSON")
    func datesArePostable() {
        #expect(WebviewPanelViewController.isPostable(Date()))
        #expect(WebviewPanelViewController.isPostable(["openedAt": Date()] as [String: Any]))
    }

    /// `NaN` and `Infinity` are the other side of the same coin: JSON refuses
    /// them, WebKit does not.
    @Test("a non-finite number is postable")
    func nonFiniteNumbersArePostable() {
        #expect(WebviewPanelViewController.isPostable(Double.nan))
        #expect(WebviewPanelViewController.isPostable(["ratio": Double.infinity] as [String: Any]))
    }

    /// The crash, at the top level. A `URL` is what `vscode.Uri` bridges to,
    /// so this is the realistic way an extension gets here.
    @Test("a native object is refused")
    func nativeObjectsAreRefused() {
        #expect(!WebviewPanelViewController.isPostable(URL(fileURLWithPath: "/tmp/x")))
        #expect(!WebviewPanelViewController.isPostable(NSObject()))
        #expect(!WebviewPanelViewController.isPostable(Data()))
    }

    /// And nested, which is the case a non-recursive check passes. The top
    /// level is a perfectly good dictionary right up until the encoder reaches
    /// the element that raises.
    @Test("a native object nested inside a good message is refused too")
    func nestedNativeObjectsAreRefused() {
        #expect(!WebviewPanelViewController.isPostable(
            ["uri": URL(fileURLWithPath: "/tmp/x")] as [String: Any]))
        #expect(!WebviewPanelViewController.isPostable(
            ["items": [1, Data(), 3] as [Any]] as [String: Any]))
        #expect(!WebviewPanelViewController.isPostable(
            [["deep": ["deeper": NSObject()]]] as [Any]))
    }

    /// A dictionary key that is not a string is the other raise, and the one
    /// no amount of checking the *values* catches. JavaScript has no such
    /// object to be turned into.
    @Test("a dictionary keyed by anything but strings is refused")
    func nonStringKeysAreRefused() {
        #expect(!WebviewPanelViewController.isPostable([1: "one"] as NSDictionary))
    }
}
