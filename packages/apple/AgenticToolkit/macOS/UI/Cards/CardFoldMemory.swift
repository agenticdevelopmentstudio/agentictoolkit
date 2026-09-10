import AppKit

/// Remembers which of a window's cards are folded, and builds every card wired
/// to that memory.
///
/// A stack of `DisclosureCardView`s needs three things that are the same in
/// every window that has one: somewhere to persist the folds, the arithmetic
/// that adds and removes a key from that set, and the rule about *when* the
/// folded state may be re-drawn. Only the first is host-specific, so it is
/// injected (`read`/`write` — typically a settings key holding a list of
/// strings) and the rest lives here. A host that owned all three itself would
/// re-derive the same two rules, and would get the second one wrong the same
/// way once: see `setCollapsed`.
///
/// Keys are the host's vocabulary — the memory never invents one, and never
/// looks inside one. What a card is *called* is the one part of folding that
/// belongs to the window drawing it (a card keyed by an account's position in a
/// list behaves very differently from one keyed by its address), so it stays
/// there.
///
/// Absent means open: a card the reader has never touched — and any card added
/// to the window later — starts unfolded, rather than needing a stored `false`
/// that a schema change could lose.
@MainActor
public final class CardFoldMemory {

    private let read: () -> [String]
    private let write: ([String]) -> Void
    private let rebuild: () -> Void

    /// - Parameters:
    ///   - read: the folded keys as last persisted.
    ///   - write: persists the folded keys.
    ///   - rebuild: re-renders the card stack. Called after a fold is recorded,
    ///     on the next turn of the runloop — never synchronously; see
    ///     `setCollapsed`.
    public init(
        read: @escaping () -> [String],
        write: @escaping ([String]) -> Void,
        rebuild: @escaping () -> Void
    ) {
        self.read = read
        self.write = write
        self.rebuild = rebuild
    }

    /// Whether the card called `key` is currently folded.
    public func isCollapsed(_ key: String) -> Bool {
        read().contains(key)
    }

    /// Records a fold and re-renders the stack.
    ///
    /// The rebuild is deferred to the next turn of the runloop rather than run
    /// inside the toggle's own action: a rebuild tears down every card,
    /// including the one whose disclosure button is still dispatching the click
    /// that got here.
    public func setCollapsed(_ collapsed: Bool, key: String) {
        write(Self.toggling(read(), key: key, collapsed: collapsed))
        DispatchQueue.main.async { [weak self] in self?.rebuild() }
    }

    /// The stored key list with `key` folded in or out — duplicate-free, and
    /// absent rather than present-and-false.
    ///
    /// Pure, so the memory's arithmetic is testable without a window.
    public static func toggling(_ keys: [String], key: String, collapsed: Bool) -> [String] {
        var next = keys.filter { $0 != key }
        if collapsed { next.append(key) }
        return next
    }

    /// A card wired to this memory: it opens in the state the memory remembers,
    /// and folding it records the fold and re-renders. Build every card in a
    /// window through here, so one card cannot quietly become the unfoldable one
    /// — or the one whose fold is forgotten.
    ///
    /// The caller adds the card's content whether or not it comes back folded
    /// (`DisclosureCardView.addContent`): a folded card that was never built is
    /// a card whose width is unknown, and unknown width is what makes a
    /// content-hugging window jump sideways on a fold.
    public func card(
        key: String,
        title: String,
        titleIsAccent: Bool = false,
        titleIcon: String? = nil,
        titleIconIsVisible: Bool = true,
        subtitle: String? = nil,
        summary: [DisclosureCardView.SummaryPart] = [],
        status: DisclosureCardView.StatusSymbol? = nil,
        isDimmed: Bool = false,
        scaledSize: CGFloat
    ) -> DisclosureCardView {
        DisclosureCardView(
            title: title,
            titleIsAccent: titleIsAccent,
            titleIcon: titleIcon,
            titleIconIsVisible: titleIconIsVisible,
            subtitle: subtitle,
            summary: summary,
            status: status,
            isCollapsed: isCollapsed(key),
            isDimmed: isDimmed,
            scaledSize: scaledSize
        ) { [weak self] collapsed in
            self?.setCollapsed(collapsed, key: key)
        }
    }
}
