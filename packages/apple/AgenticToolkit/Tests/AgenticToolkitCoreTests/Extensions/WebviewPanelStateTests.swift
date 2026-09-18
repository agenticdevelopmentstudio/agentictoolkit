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

    @Test("a panel round-trips through its stored text")
    func roundTripsThroughText() throws {
        let original = WebviewPanelState(
            viewType: "markdown.preview", title: "Preview README.md",
            state: #"{"scrollTop":420}"#)

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
            viewType: "markdown.preview", title: "Preview", state: nil)

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
            json: WebviewPanelState(viewType: "v", title: "t", state: state).encoded())

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
            viewType: "vendor.view-type_2", title: #"Preview "a"b.md — café"#, state: nil)

        let restored = try WebviewPanelState(json: original.encoded())

        #expect(restored == original)
    }
}
