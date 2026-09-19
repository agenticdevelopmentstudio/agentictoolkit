//
//  UpstreamDivergence.swift
//  AgenticToolkit
//

import Foundation

/// One place where this app knowingly does less than VS Code does.
///
/// These are not bugs and not TODOs. Each is a narrowing that was decided on
/// deliberately, with a reason, and each has until now lived only as a comment
/// beside the code that implements it. A comment is invisible to the person
/// running an extension that trips over the narrowing: they see tokens that did
/// not highlight and have no way to learn that the omission was chosen rather
/// than broken.
///
/// The catalogue exists so that a narrowing can be *observed* while real
/// extensions are exercised, rather than rediscovered by reading the source.
/// A row that never fires is a narrowing nothing in practice depends on; a row
/// that fires constantly is the next thing to implement. Neither fact is
/// available from the code alone.
public struct UpstreamDivergence: Sendable, Hashable, Identifiable, Codable {

    /// How, or whether, this narrowing can be seen happening at runtime.
    ///
    /// The distinction is the whole reason a count is trustworthy. A `.counted`
    /// row at zero means the code that would have recorded it did not run: real
    /// evidence. A `.declared` row at zero means nothing whatsoever — there is
    /// no call site, because the narrowing takes the form of a capability we
    /// never advertised, so the server simply never sends the thing we would
    /// have had to drop. Showing both as "0" without the label would invite
    /// exactly the wrong conclusion about the second kind.
    public enum Detection: String, Sendable, Hashable, Codable {
        /// There is a call site. A count is evidence.
        case counted
        /// There is no call site and cannot be one. Documentation only.
        case declared
    }

    /// Stable identifier, used as the dedupe key in the ledger and as the sort
    /// order of a report. Stable across releases on purpose: a row's history is
    /// only readable if the row keeps its name.
    public let id: String

    /// Where in the app this happens, in the words a user would use — the
    /// heading a report groups under.
    public let area: String

    /// What VS Code does.
    public let upstreamBehaviour: String

    /// What we do instead.
    public let ourBehaviour: String

    /// Why. This is the part that stops the row reading as an apology: most of
    /// these are narrowings the renderer here cannot represent at all, not
    /// corners cut.
    public let rationale: String

    public let detection: Detection

    public init(
        id: String,
        area: String,
        upstreamBehaviour: String,
        ourBehaviour: String,
        rationale: String,
        detection: Detection
    ) {
        self.id = id
        self.area = area
        self.upstreamBehaviour = upstreamBehaviour
        self.ourBehaviour = ourBehaviour
        self.rationale = rationale
        self.detection = detection
    }
}

extension UpstreamDivergence {

    /// A document outside the project window's workspace root is never
    /// announced to any language server.
    ///
    /// This is Stage 3's "D4 filter" — `LanguageServerDocumentSync`'s
    /// `isInWorkspaceScope(_:)`, whose own doc comment calls it an **accepted
    /// gap**. The ledger entry that recorded the ruling behind it is gone; the
    /// row below is what replaces it, and unlike the ruling it can be measured.
    public static let documentOutsideWorkspaceScope = UpstreamDivergence(
        id: "language-servers.document-outside-workspace",
        area: "Language servers",
        upstreamBehaviour: """
            VS Code matches a document against each extension's \
            `documentSelector` and opens it on every server that claims the \
            language, wherever the file happens to live. A file opened from \
            outside the workspace still gets completions, diagnostics and \
            hovers.
            """,
        ourBehaviour: """
            Only documents under the project window's own workspace root are \
            announced. A file outside it is never sent `didOpen`, so it has \
            no language intelligence at all — and because the notifications \
            that follow are gated on having been opened, it never acquires \
            any later either.
            """,
        rationale: """
            The document store is app-wide while a language server belongs to \
            one project window, so an unscoped sync would feed every server \
            every window's files. The scope test is the workspace URL rather \
            than the server's own root — which is found by walking up for a \
            root marker and can therefore be an ancestor of it — so the \
            filter also turns away some documents the server itself would \
            have accepted. That is the conservative side of the error, and \
            narrowing it would cost an `await` per document event on the \
            synchronous store-callback path.
            """,
        detection: .counted
    )

    /// Semantic tokens that overlap a token already emitted are dropped.
    public static let semanticTokenOverlapDropped = UpstreamDivergence(
        id: "semantic-tokens.overlapping-dropped",
        area: "Semantic highlighting",
        upstreamBehaviour: """
            VS Code accepts overlapping semantic tokens and resolves them by \
            layering, so a server may send a broad token and then a narrower \
            one inside it.
            """,
        ourBehaviour: """
            The second token is dropped. Highlighting comes out as the first \
            token said, and the refinement is lost.
            """,
        rationale: """
            The editor applies highlight ranges as a flat, sorted, \
            non-overlapping list; there is no layer to resolve overlaps in. \
            The client capability `overlappingTokenSupport` is declared false \
            for the same reason, so a well-behaved server should never produce \
            these — a hit here means a server ignored the capability.
            """,
        detection: .counted
    )

    /// A token type the server's legend names but the theme cannot map.
    public static let semanticTokenTypeUnmapped = UpstreamDivergence(
        id: "semantic-tokens.type-unmapped",
        area: "Semantic highlighting",
        upstreamBehaviour: """
            VS Code maps every semantic token type through its theme's token \
            colour rules, falling back through a standard hierarchy so an \
            unfamiliar type still receives a colour.
            """,
        ourBehaviour: "The token is skipped and keeps its syntactic colour.",
        rationale: """
            Our themes map a fixed set of capture names. A type outside that \
            set has no colour to fall back to, and inventing one would be \
            worse than leaving the syntactic highlighting in place.
            """,
        detection: .counted
    )

    /// Token modifiers are accepted and then ignored.
    public static let semanticTokenModifiersIgnored = UpstreamDivergence(
        id: "semantic-tokens.modifiers-ignored",
        area: "Semantic highlighting",
        upstreamBehaviour: """
            VS Code styles on modifiers as well as types — `readonly`, \
            `deprecated`, `async` and the rest each carry their own theme \
            rules, which is how a deprecated symbol gets struck through.
            """,
        ourBehaviour: """
            Modifiers are parsed out of the encoded token stream and then \
            discarded. Two symbols of the same type look identical however \
            they are modified.
            """,
        rationale: """
            The highlight pipeline is dead end to end for modifiers: the token \
            representation hardcodes an empty modifier set and the theme's \
            capture mapping ignores the modifier set it is passed. Wiring it \
            is a change to both, not a change here.
            """,
        detection: .counted
    )

    /// A token naming a line the document does not have.
    public static let semanticTokenLineOutOfRange = UpstreamDivergence(
        id: "semantic-tokens.line-out-of-range",
        area: "Semantic highlighting",
        upstreamBehaviour: """
            VS Code clamps a token whose line is past the end of the document, \
            which happens when a server answers against a revision the editor \
            has already moved past.
            """,
        ourBehaviour: "The token is dropped.",
        rationale: """
            Highlight ranges are resolved against the document the response is \
            attributed to, so by construction the line should exist. A hit \
            here is a real finding: it means a stale response was applied to a \
            document it did not describe.
            """,
        detection: .counted
    )

    /// Multi-line semantic tokens are never requested.
    public static let semanticTokenMultilineUnsupported = UpstreamDivergence(
        id: "semantic-tokens.multiline-unsupported",
        area: "Semantic highlighting",
        upstreamBehaviour: """
            VS Code declares `multilineTokenSupport`, so a server may emit one \
            token spanning several lines — a here-doc or a multi-line string \
            arrives as a single token.
            """,
        ourBehaviour: """
            The capability is declared false, so a conforming server splits \
            such a construct into one token per line before sending it.
            """,
        rationale: """
            A highlight range here is an `NSRange` into one line's text. There \
            is nothing to count: the narrowing is upstream of us, in what the \
            server chooses to send, and a conforming server's split output is \
            indistinguishable from output it would have produced anyway.
            """,
        detection: .declared
    )

    /// Every divergence this app knows about, in report order.
    ///
    /// Adding a `static let` above is not enough — a row absent from this list
    /// is absent from the settings panel and from `citations`-style audits.
    /// The catalogue is the list, not the namespace.
    public static let known: [UpstreamDivergence] = [
        documentOutsideWorkspaceScope,
        semanticTokenLineOutOfRange,
        semanticTokenModifiersIgnored,
        semanticTokenMultilineUnsupported,
        semanticTokenOverlapDropped,
        semanticTokenTypeUnmapped
    ]
}
