<!-- leaf: implement-composable-tabs/window-controller--part-3 · source: composable-tabs-window-controller.md -->

# ComposableTabsWindowController — continued (part 3)

## Design Decisions

**Decision**: Persist the edge top-up after `installInitialTabs()` restores
the active tab, never before it.
**Rationale**: `persistAllTabs()` writes whichever tab is active at the
moment it runs; writing before the restore would capture the tab that
`insertTab` auto-selected (the first tab of the first enabled edge) instead
of the project's remembered selection, and the next launch would silently
open on the wrong tab even though the current session looked correct.
**Approved**: pending

**Decision**: Suppress `didSelectTab`'s persist, focus-restore, and
chrome-refresh side effects while `reloadTabs()`'s removal loop is running
(`isReloadingTabs`).
**Rationale**: `removeTab` fires `didSelectTab` for whichever member it
activates next; running the full side-effect chain mid-loop would persist a
shrinking, half-removed tab set, schedule first-responder work against a
split about to be discarded, and recompute chrome against tabs that are
half gone.
**Approved**: pending

**Decision**: Debounce the focused-leaf persist by 250ms while persisting
every structural change (split, close, add, remove, reorder, select, edge
toggle) synchronously.
**Rationale**: a divider position is something the user placed by hand and
expects to find again; the focused leaf is a first-responder position the
next launch re-derives on its own, so only it can tolerate — and benefits
from — coalesced writes.
**Approved**: pending

**Decision**: Flush any pending divider-thickness persist during
`windowWillClose` before raising `isClosing`, gated on the project already
having stored tabs.
**Rationale**: a window closed before its project finished opening has a
pending thickness write armed by the very first, placeholder layout pass;
flushing it unconditionally would overwrite a project that has never been
saved with a placeholder arrangement, so the flush only runs when
`storedTabs() != nil`.
**Approved**: pending

**Decision**: Write the help drawer's remembered tab and width only after
`hasDisclosedHelp` becomes true, never on window close alone.
**Rationale**: `setSetting` treats "never set" and "reset to the default"
identically; writing a default row on every window close for a project
whose help was never opened would be indistinguishable from the user having
explicitly chosen that default.
**Approved**: pending

**Decision**: When `enabledTabEdgeNames` is assigned, enable every named
edge before disabling any edge not named.
**Rationale**: `setEdgeEnabled` refuses to disable the last enabled edge;
processing removals before additions would make some legal reassignments
(for example, moving the only enabled edge from top to bottom) fail,
because the source edge would still read as "the last one" at the moment
its disable is attempted.
**Approved**: pending

**Decision**: Ship every user-facing string in this file — toolbar and
titlebar labels, the help topic bodies, and the default tab title
`"Tab \(n)"` — as a hardcoded English literal rather than routing them
through a localization key now.
**Rationale**: the window controller predates this project's localization
pass, so none of these strings has a translation to diverge from yet, and
routing them through `NSLocalizedString`/a string catalog today would be
speculative work with nothing to validate it against. `Localization` above
enumerates the literals so the conversion has a ready checklist; the payoff
trigger for doing it is the product actually shipping a non-English build.
**Approved**: pending

**Decision**: Do not add error handling, logging, or retry around
`project.setSetting(_:to:)` or `project.persistTabs(...)` failures in this
controller.
**Rationale**: both calls already swallow their own errors one layer down,
in `ProjectWorkspace`; this controller has no additional recovery to offer
and no user-facing affordance to retry a settings write from a window
controller. The payoff trigger for revisiting this is a workflow that
depends on a persist actually succeeding (for example cross-device sync),
or a reported case of state loss that traces back to a swallowed write —
neither has occurred yet.
**Approved**: pending
