import Foundation
import Testing
@testable import AgenticToolkitCore

/// What survives a quit: everything needed to put a webview panel back where it
/// was, as the single string the pane-state store holds.
///
/// The interesting property is that the extension's own state is carried
/// *verbatim*. It goes back into a `<script>` element on restore, so a
/// re-encoding that reorders keys or re-escapes a character is not cosmetic —
/// it is a different value than the one the extension saved.
@Suite
struct WebviewPanelStateTests {

    /// The posture every panel here is created with unless the test is
    /// about the options themselves: scripts off, default roots.
    private let defaultOptions = WebviewPanelOptions(
        enableScripts: nil, enableForms: nil, localResourceRoots: nil)

    @Test("a panel round-trips through its stored text")
    func roundTripsThroughText() throws {
        let original = WebviewPanelState(
            viewType: "markdown.preview", title: "Preview README.md",
            state: #"{"scrollTop":420}"#, options: defaultOptions)

        let restored = try WebviewPanelState(json: original.encoded())

        #expect(restored == original)
    }

    /// A panel that never called `setState` is not the same as one that saved a
    /// null — `WebviewHostDocument` renders the first as `undefined`, which is
    /// how an extension tells a restore from a first run. Collapsing the two
    /// here would undo that distinction one layer down.
    @Test("a panel that never saved state restores with none")
    func absentStateStaysAbsent() throws {
        let original = WebviewPanelState(
            viewType: "markdown.preview", title: "Preview", state: nil, options: defaultOptions)

        let restored = try WebviewPanelState(json: original.encoded())

        #expect(restored.state == nil)
    }

    /// The extension's state is JSON text this never parses: it is stored as a
    /// string and handed back as a string. Anything else means a panel restores
    /// with a value its extension did not write.
    @Test(
        "the extension's own state is carried through byte for byte",
        arguments: [
            #"{"a":1}"#,
            #"{ "a" : 1 }"#,
            #"{"b":2,"a":1}"#,
            #"{"note":"line\nbreak \"quoted\" café"}"#,
            #"{"markup":"<\/script>"}"#,
            "null",
            "[]"
        ]
    )
    func theExtensionsStateIsCarriedVerbatim(_ state: String) throws {
        let restored = try WebviewPanelState(
            json: WebviewPanelState(
                viewType: "v", title: "t", state: state, options: defaultOptions).encoded())

        #expect(restored.state == state)
    }

    /// Pane state outlives the build that wrote it. A panel stored by a newer
    /// version, then read by an older one, must come back as a panel — dropping
    /// it because of a field nobody has heard of loses the user's tab to a
    /// downgrade.
    @Test("a field this version does not know is ignored")
    func unknownFieldsAreIgnored() throws {
        let stored = #"{"viewType":"markdown.preview","title":"Preview","iconPath":"a.png"}"#

        let restored = try WebviewPanelState(json: stored)

        #expect(restored.viewType == "markdown.preview")
        #expect(restored.title == "Preview")
    }

    /// The view type is what finds the serializer that knows how to rebuild
    /// this panel. Without one there is nothing to guess at, and a guess would
    /// hand the panel to the wrong provider — so this refuses rather than
    /// defaulting.
    @Test("a panel with no view type is refused")
    func aMissingViewTypeIsRefused() {
        #expect(throws: (any Error).self) {
            try WebviewPanelState(json: #"{"title":"Preview"}"#)
        }
    }

    @Test(
        "text that is not a stored panel is refused",
        arguments: ["", "not json", "{", "[]", #""markdown.preview""#]
    )
    func malformedTextIsRefused(_ stored: String) {
        #expect(throws: (any Error).self) {
            try WebviewPanelState(json: stored)
        }
    }

    /// Titles come from extensions and hold whatever the extension put there —
    /// a file name with a quote in it is the ordinary case, not an attack.
    @Test("awkward titles and view types survive")
    func awkwardTitlesSurvive() throws {
        let original = WebviewPanelState(
            viewType: "vendor.view-type_2", title: #"Preview "a"b.md — café"#, state: nil,
            options: defaultOptions)

        let restored = try WebviewPanelState(json: original.encoded())

        #expect(restored == original)
    }

    // MARK: - The options a restored panel has to be built with

    /// `enableScripts` is baked into the `WKWebViewConfiguration` at first
    /// load, so a restored panel that guessed it would come back unable to run
    /// the page its extension is about to hand it — and nothing the extension
    /// could do afterwards would fix it.
    @Test("a scripted panel comes back scripted")
    func scriptsSurviveTheRoundTrip() throws {
        let original = WebviewPanelState(
            viewType: "markdown.preview", title: "Preview", state: nil,
            options: WebviewPanelOptions(
                enableScripts: true, enableForms: nil, localResourceRoots: nil))

        let restored = try WebviewPanelState(json: original.encoded())

        #expect(restored.options.enableScripts)
        #expect(restored.options.enableForms)
    }

    /// The dangerous direction. A panel that declared *no* roots renounced file
    /// access entirely; if that decays to "declared nothing" it comes back with
    /// its extension directory and the whole workspace readable — access the
    /// extension explicitly gave up.
    @Test("a panel that renounced file access does not get it back")
    func anEmptyRootDeclarationSurvives() throws {
        let original = WebviewPanelState(
            viewType: "markdown.preview", title: "Preview", state: nil,
            options: WebviewPanelOptions(
                enableScripts: true, enableForms: nil, localResourceRoots: []))

        let restored = try WebviewPanelState(json: original.encoded())

        #expect(restored.options.resourceRoots(
            extensionDirectory: URL(fileURLWithPath: "/ext"),
            workspaceRoots: [URL(fileURLWithPath: "/work")]).isEmpty)
    }

    @Test("declared roots come back as the same directories")
    func declaredRootsSurvive() throws {
        let declared = [URL(fileURLWithPath: "/ext/media"), URL(fileURLWithPath: "/work/docs")]
        let original = WebviewPanelState(
            viewType: "markdown.preview", title: "Preview", state: nil,
            options: WebviewPanelOptions(
                enableScripts: nil, enableForms: nil, localResourceRoots: declared))

        let restored = try WebviewPanelState(json: original.encoded())

        #expect(restored.options.resourceRoots(
            extensionDirectory: URL(fileURLWithPath: "/ext"),
            workspaceRoots: [URL(fileURLWithPath: "/work")]).map(\.path)
            == declared.map(\.path))
    }

    /// An entry written before options were stored is still a panel the user
    /// had open. It must come back — but with the safe posture, not with
    /// capabilities nobody recorded it having.
    @Test("a panel stored before options existed comes back unscripted")
    func absentOptionsDecodeToTheSafePosture() throws {
        let stored = #"{"viewType":"markdown.preview","title":"Preview"}"#

        let restored = try WebviewPanelState(json: stored)

        #expect(restored.options.enableScripts == false)
        #expect(restored.options.enableForms == false)
        #expect(restored.options.resourceRoots(
            extensionDirectory: URL(fileURLWithPath: "/ext"),
            workspaceRoots: [URL(fileURLWithPath: "/work")]).map(\.path) == ["/ext", "/work"])
    }
}
