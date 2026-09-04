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
    // its public API). Below, each of the four `nonisolated(unsafe)`
    // candidates is handled on its own terms rather than under one blanket
    // rationale — two turned out not to need it at all, one is moved into a
    // small `@MainActor` box reached via `assumeIsolated` (so the compiler
    // checks it rather than a comment alone), and one (`backingStore`) is
    // kept `nonisolated(unsafe)` because AppKit's own `Any`-typed attribute
    // dictionaries cannot be proven `Sendable`, which forecloses the
    // box-and-`assumeIsolated` approach for it specifically — see its own
    // comment below.

    // `TextDocument` is `@MainActor`-isolated, and Swift treats a
    // global-actor-isolated class as implicitly `Sendable` (all of its
    // mutable state is only ever reachable while isolated to that actor), so
    // this property needs no `nonisolated(unsafe)` of its own — only the
    // isolated *methods* called on it below need `assumeIsolated`.
    public let document: TextDocument

    /// Holds the same characters as `document.text`, plus the display
    /// attributes AppKit needs for rendering. `document` remains the
    /// authority on *content* — this is purely the rendering-facing mirror.
    ///
    /// **Why this one stays `nonisolated(unsafe)` rather than following
    /// `localEditGuard` into a boxed, `assumeIsolated`-mediated
    /// `@MainActor` property:** `attributes(at:effectiveRange:)` must return
    /// `[NSAttributedString.Key: Any]` across the boundary
    /// `MainActor.assumeIsolated`'s closure result crosses, and `Any` cannot
    /// be proven `Sendable` — the compiler rejects `MainActor.assumeIsolated
    /// { state.backingStore.attributes(...) }` outright
    /// ("type 'Any' does not conform to the 'Sendable' protocol"), not as a
    /// stylistic preference but as a hard type-system wall. Wrapping the
    /// result in an `@unchecked Sendable` box at each call site would just
    /// relocate the same unchecked assertion into a harder-to-audit spot, so
    /// this stays a `nonisolated(unsafe)` stored property instead: what
    /// actually guarantees no data race is that every one of the four
    /// `NSTextStorage` primitive overrides below that touch it — `string`,
    /// `attributes(at:effectiveRange:)`, `replaceCharacters(in:with:)`,
    /// `setAttributes(_:range:)` — is called by AppKit only on the main
    /// thread for this app's actual usage (a single `NSTextView` per
    /// document, no background layout), the same thread `applyExternalChanges`
    /// below (an ordinary `@MainActor` method) already runs on — so every
    /// touch of `backingStore`, from either direction, is confined to one
    /// thread even though the compiler cannot see that confinement through
    /// AppKit's `nonisolated` superclass declarations.
    private nonisolated(unsafe) let backingStore: NSMutableAttributedString

    /// The one piece of mutable state that can be moved out of `self`
    /// (`NSObject`-rooted, hence not implicitly `Sendable`) into its own
    /// plain `@MainActor` class, which *is* implicitly `Sendable` — exactly
    /// like `document` above. That makes a `let` reference to it safe to
    /// store with no `nonisolated(unsafe)`, and safe to capture (a local
    /// copy, never `self`) into a `MainActor.assumeIsolated` closure from
    /// `replaceCharacters(in:with:)` below, because a `Bool` result (unlike
    /// `[NSAttributedString.Key: Any]`) is trivially `Sendable`. The result:
    /// every read or write of `isApplyingLocalEdit` is a real,
    /// compiler-checked `@MainActor` access, not an unchecked assertion.
    @MainActor
    private final class LocalEditGuard {
        /// Guards against Direction 1 (this storage pushes a local edit into
        /// the document) re-entering Direction 2 (the document's change
        /// notification rewrites this storage). Direction 1's push mutates
        /// `document`, which fires the very same notification a reload from
        /// disk would — without this guard, Direction 2 would rewrite the
        /// storage the user is mid-edit in, corrupting the text and very
        /// likely trapping on a range that no longer describes anything. Set
        /// only around that push; checked at the top of the Direction-2
        /// handler. Do not delete this thinking it's dead — it is the only
        /// thing standing between typing and a crash.
        var isApplyingLocalEdit = false
    }

    private let localEditGuard = LocalEditGuard()

    /// Keeps the Direction-2 handler registered on `document` alive for as
    /// long as this storage exists; dropped in `deinit`. Written only from
    /// `init`, an `@MainActor`-isolated context (this whole class is
    /// `@MainActor`, and nothing narrows `init` to `nonisolated`), and never
    /// touched by any of the `nonisolated` primitive overrides — so, like
    /// `externalChangeApplicationCount` below, it needs no
    /// `nonisolated(unsafe)` at all.
    private var changeObservation: TextDocumentObservation?

    /// Number of times the Direction-2 handler actually rewrote the backing
    /// store (i.e. was not turned away by `isApplyingLocalEdit`). Internal
    /// rather than private so `TextDocumentStorageTests` can assert on it
    /// through `@testable import` — the reentrancy guarantee is tested by
    /// counting invocations, not by hoping nothing crashes. Mutated only
    /// from `applyExternalChanges`, an ordinary (non-override) method of
    /// this `@MainActor` class and therefore itself `@MainActor`-isolated —
    /// never touched by a `nonisolated` primitive override — so this needs
    /// no `nonisolated(unsafe)` either.
    private(set) var externalChangeApplicationCount = 0

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
    // isolation. `backingStore` is read/mutated directly here (see its own
    // comment above for why it stays `nonisolated(unsafe)`); `localEditGuard`
    // is read through a local copy plus `MainActor.assumeIsolated` (see its
    // comment above for why that is possible where it is not for
    // `backingStore`). Calling an actor-isolated *method* on `document`
    // (`range(for:)`, `apply(_:)`) follows the `assumeIsolated` shape too,
    // with a local copy of `document` instead — never `self`, because
    // "sending" a non-`Sendable`, aliased `self` into that closure is exactly
    // the race the compiler cannot rule out (the same diagnostic fixed in
    // `ComposableTabsViewController.swift`).

    override public var string: String {
        // See the class-level comment on `backingStore`: correctness here
        // rests entirely on AppKit calling this only from the main thread.
        // Fail loudly the moment that assumption is ever false, rather than
        // silently racing.
        dispatchPrecondition(condition: .onQueue(.main))
        return backingStore.string
    }

    override public func attributes(
        at location: Int,
        effectiveRange range: NSRangePointer?
    ) -> [NSAttributedString.Key: Any] {
        // See the class-level comment on `backingStore`: correctness here
        // rests entirely on AppKit calling this only from the main thread.
        // Fail loudly the moment that assumption is ever false, rather than
        // silently racing.
        dispatchPrecondition(condition: .onQueue(.main))
        return backingStore.attributes(at: location, effectiveRange: range)
    }

    /// Direction 1 — AppKit (or a caller acting on its behalf) edits the
    /// storage: apply it to the backing string, tell the layout manager, then
    /// push the same edit into `document`.
    override public func replaceCharacters(in range: NSRange, with str: String) {
        // See the class-level comment on `backingStore`: correctness here
        // rests entirely on AppKit calling this only from the main thread.
        // Fail loudly the moment that assumption is ever false, rather than
        // silently racing.
        dispatchPrecondition(condition: .onQueue(.main))

        let currentDocument = document
        let guardState = localEditGuard

        // Convert the range against `document` BEFORE mutating the backing
        // string: once `backingStore` is mutated its offsets describe the
        // new text, and `document` (not yet touched) still describes the
        // old one — converting after would resolve against the wrong text.
        let editedRange = MainActor.assumeIsolated { currentDocument.range(for: range) }

        backingStore.replaceCharacters(in: range, with: str)
        let changeInLength = (str as NSString).length - range.length
        edited([.editedCharacters, .editedAttributes], range: range, changeInLength: changeInLength)

        MainActor.assumeIsolated { guardState.isApplyingLocalEdit = true }
        defer { MainActor.assumeIsolated { guardState.isApplyingLocalEdit = false } }
        _ = MainActor.assumeIsolated {
            currentDocument.apply([TextEdit(range: editedRange, newText: str)])
        }
    }

    override public func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        // See the class-level comment on `backingStore`: correctness here
        // rests entirely on AppKit calling this only from the main thread.
        // Fail loudly the moment that assumption is ever false, rather than
        // silently racing.
        dispatchPrecondition(condition: .onQueue(.main))
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
        guard !localEditGuard.isApplyingLocalEdit else { return }
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
