//
//  WebviewPanelState.swift
//  AgenticToolkit
//

import Foundation

/// Thrown where nothing should be able to throw.
public enum WebviewPanelStateError: Error, Equatable {
    /// `JSONEncoder` emitted bytes that are not UTF-8 — which it does not, by
    /// definition of JSON. This case exists because the alternative is a
    /// force-unwrap that is just as unreachable and far worse if it ever is
    /// not (`fail-fast`, but as a thrown error rather than a dead process).
    case encodedTextIsNotUTF8
}

/// Everything needed to put a webview panel back after a quit, as the single
/// string the pane-state store holds.
///
/// `ProjectWorkspace.setPaneState(nodeID:key:value:)` stores one `String?` per
/// key, so every caller that wants structure encodes its own JSON. This is that
/// encoding, written once rather than at the call site (`dry`), because getting
/// it subtly wrong is how a panel comes back with a value its extension never
/// saved.
public struct WebviewPanelState: Codable, Equatable, Sendable {

    /// The view type its serializer is registered under, and the activation
    /// event (`onWebviewPanel:<viewType>`) that wakes the extension owning it.
    ///
    /// The owning extension is deliberately *not* stored: it is derivable from
    /// this, and a second copy of a derivable fact is one that can disagree
    /// with the first.
    public let viewType: String

    /// The panel's title at the moment it was stored.
    public let title: String

    /// The JSON text the page last passed to `setState`, or `nil` if it never
    /// did — carried as text, never parsed.
    ///
    /// It goes straight back into a `<script>` element on restore (see
    /// `WebviewHostDocument`), so re-encoding it would reorder keys and
    /// re-escape characters: a different value than the extension saved, by a
    /// layer that has no business reading it at all.
    public let state: String?

    /// What the panel was created with.
    ///
    /// Stored because `WKWebViewConfiguration` is built once, in
    /// `WebviewPanelViewController.loadView()`, and `enableScripts` is baked
    /// into it there: a restored panel that guessed `false` would come back
    /// unable to run the page its extension is about to hand it, and nothing
    /// the extension could do afterwards would fix it. The declared resource
    /// roots are in here for the same reason in reverse — a panel that
    /// renounced file access must not get it back by being restored.
    public let options: WebviewPanelOptions

    public init(
        viewType: String,
        title: String,
        state: String?,
        options: WebviewPanelOptions
    ) {
        self.viewType = viewType
        self.title = title
        self.state = state
        self.options = options
    }

    /// The single string the pane-state store holds.
    ///
    /// Keys are sorted, so an unchanged panel encodes to an unchanged string
    /// and a store that notifies on change stays quiet.
    public func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let text = String(bytes: try encoder.encode(self), encoding: .utf8) else {
            throw WebviewPanelStateError.encodedTextIsNotUTF8
        }
        return text
    }

    /// Reads back what `encoded()` wrote.
    ///
    /// Throws on anything that is not a stored panel, which the caller is
    /// expected to treat as a pane that does not come back — a corrupted entry
    /// should cost one tab, not the window it is in.
    public init(json: String) throws {
        self = try JSONDecoder().decode(Self.self, from: Data(json.utf8))
    }

    private enum CodingKeys: String, CodingKey {
        case viewType, title, state, options
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A missing title is survivable — an untitled tab is still the user's
        // tab. A missing view type is not: it names the serializer that knows
        // how to rebuild this panel, and a default would hand the panel to
        // whichever provider happened to answer to the empty string.
        viewType = try container.decode(String.self, forKey: .viewType)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        state = try container.decodeIfPresent(String.self, forKey: .state)
        // Absent options decode to the safe posture — no scripts, no forms,
        // and the default roots — rather than throwing. An entry written
        // before options were stored is still a panel the user had open, and
        // the extension re-renders into it either way; what it must not do is
        // come back with capabilities nobody recorded it having.
        options = try container.decodeIfPresent(WebviewPanelOptions.self, forKey: .options)
            ?? WebviewPanelOptions(enableScripts: nil, enableForms: nil, localResourceRoots: nil)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(viewType, forKey: .viewType)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(state, forKey: .state)
        try container.encode(options, forKey: .options)
    }
}
