import AgenticToolkitLanguage
import AppKit
import LanguageServerProtocol

/// The AppKit face of a `TextDocument`: an `NSTextStorage` a text view can be
/// backed by directly, kept in sync with the document in both directions.
/// Mirrors the `SemanticPalette` / `SemanticPalette+NSColor` split — the
/// document (`AgenticToolkitLanguage`) is the Foundation-only, daemon-safe
/// model; this is its AppKit bridge, and nothing else
/// (`separation-of-concerns`): no filesystem access, no autosave scheduler
/// ownership.
@MainActor
public final class TextDocumentStorage: NSTextStorage {

    // `NSTextStorage`'s four primitive overrides below are declared
    // `nonisolated` in the AppKit overlay (text storage has historically been
    // touchable off the main thread), so they do not inherit this class's
    // `@MainActor` isolation the way an ordinary method would — Swift will
    // not let an override narrow a nonisolated superclass requirement to
    // `@MainActor`. In practice AppKit only ever calls them on the main
    // thread (the same guarantee this class's own `@MainActor` documents for
    // its public API), so the properties they touch are marked
    // `nonisolated(unsafe)` here rather than fought with `assumeIsolated`,
    // which cannot "send" a non-`Sendable` `self` across the boundary it
    // asserts. This is the standard shape for bridging a non-actor-aware
    // AppKit superclass, not a shortcut around getting isolation right.

    // `TextDocument` is `@MainActor`-isolated, and Swift treats a
    // global-actor-isolated class as implicitly `Sendable` (all of its
    // mutable state is only ever reachable while isolated to that actor), so
    // this property needs no `nonisolated(unsafe)` of its own — only the
    // isolated *methods* called on it below need `assumeIsolated`.
    public let document: TextDocument

    /// Holds the same characters as `document.text`, plus the display
    /// attributes AppKit needs for rendering. `document` remains the
    /// authority on *content* — this is purely the rendering-facing mirror.
    private nonisolated(unsafe) let backingStore: NSMutableAttributedString

    /// Keeps the Direction-2 handler registered on `document` alive for as
    /// long as this storage exists; dropped in `deinit`.
    private nonisolated(unsafe) var changeObservation: TextDocumentObservation?

    /// Guards against Direction 1 (this storage pushes a local edit into the
    /// document) re-entering Direction 2 (the document's change notification
    /// rewrites this storage). Direction 1's push mutates `document`, which
    /// fires the very same notification a reload from disk would — without
    /// this guard, Direction 2 would rewrite the storage the user is
    /// mid-edit in, corrupting the text and very likely trapping on a range
    /// that no longer describes anything. Set only around that push; checked
    /// at the top of the Direction-2 handler. Do not delete this thinking
    /// it's dead — it is the only thing standing between typing and a crash.
    private nonisolated(unsafe) var isApplyingLocalEdit = false

    /// Number of times the Direction-2 handler actually rewrote the backing
    /// store (i.e. was not turned away by `isApplyingLocalEdit`). Internal
    /// rather than private so `TextDocumentStorageTests` can assert on it
    /// through `@testable import` — the reentrancy guarantee is tested by
    /// counting invocations, not by hoping nothing crashes.
    private(set) nonisolated(unsafe) var externalChangeApplicationCount = 0

    public init(document: TextDocument) {
        self.document = document
        self.backingStore = NSMutableAttributedString(string: document.text)
        super.init()

        // [weak self]: this closure is retained by `document`'s change
        // handler dictionary for as long as `changeObservation` (held by
        // `self`) is alive. Capturing `self` strongly here would make
        // `document` transitively keep `self` alive forever, and `self`
        // already keeps `document` alive directly — a retain cycle.
        changeObservation = document.addChangeHandler { [weak self] _, changes in
            self?.applyExternalChanges(changes)
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("TextDocumentStorage does not support NSCoding")
    }

    @available(*, unavailable)
    public required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        fatalError("TextDocumentStorage does not support pasteboard reading")
    }

    // MARK: - NSTextStorage primitives
    //
    // `NSTextStorage`'s primitives are declared `nonisolated` in the AppKit
    // overlay (text storage has historically been touchable off the main
    // thread), so overriding them does not inherit this class's `@MainActor`
    // isolation. `backingStore`, `document` and `isApplyingLocalEdit` are all
    // `nonisolated(unsafe)` for exactly this reason: AppKit only ever calls
    // these four methods on the main thread — the same guarantee this type's
    // own `@MainActor` documents for its public API — so reading them here
    // needs no further ceremony. Calling an actor-isolated *method* on
    // `document` (`range(for:)`, `apply(_:)`) still needs `assumeIsolated`;
    // it is given a local copy of `document`, never `self`, because "sending"
    // `self` — an object other code definitely holds a reference to — into
    // that closure is exactly the race the compiler cannot rule out.

    override public var string: String {
        backingStore.string
    }

    override public func attributes(
        at location: Int,
        effectiveRange range: NSRangePointer?
    ) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    /// Direction 1 — AppKit (or a caller acting on its behalf) edits the
    /// storage: apply it to the backing string, tell the layout manager, then
    /// push the same edit into `document`.
    override public func replaceCharacters(in range: NSRange, with str: String) {
        let currentDocument = document

        // Convert the range against `document` BEFORE mutating the backing
        // string: once `backingStore` is mutated its offsets describe the
        // new text, and `document` (not yet touched) still describes the
        // old one — converting after would resolve against the wrong text.
        let editedRange = MainActor.assumeIsolated { currentDocument.range(for: range) }

        backingStore.replaceCharacters(in: range, with: str)
        let changeInLength = (str as NSString).length - range.length
        edited([.editedCharacters, .editedAttributes], range: range, changeInLength: changeInLength)

        isApplyingLocalEdit = true
        _ = MainActor.assumeIsolated {
            currentDocument.apply([TextEdit(range: editedRange, newText: str)])
        }
        isApplyingLocalEdit = false
    }

    override public func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }

    // MARK: - Direction 2 — the document changes from outside

    /// A reload from disk, an LSP workspace edit, or a future extension-host
    /// edit — anything that mutates `document` other than this storage
    /// itself. Rewrites the backing string wholesale to match `document.text`
    /// rather than trying to replay the incoming change's own range: by the
    /// time this fires, `document` has already applied every change in the
    /// batch and rebuilt its line index, so re-deriving a partial `NSRange`
    /// from a change event's (pre-batch) `LSPRange` would resolve against the
    /// wrong line index. A full rewrite is always correct and this is not a
    /// hot path — Direction 1 (typing) never reaches it, guarded out below.
    private func applyExternalChanges(_ changes: [TextDocumentContentChangeEvent]) {
        guard !isApplyingLocalEdit else { return }
        guard !changes.isEmpty else { return }

        externalChangeApplicationCount += 1

        let newText = document.text
        let fullRange = NSRange(location: 0, length: backingStore.length)
        let changeInLength = (newText as NSString).length - fullRange.length

        beginEditing()
        backingStore.replaceCharacters(in: fullRange, with: newText)
        edited([.editedCharacters, .editedAttributes], range: fullRange, changeInLength: changeInLength)
        endEditing()
    }
}
