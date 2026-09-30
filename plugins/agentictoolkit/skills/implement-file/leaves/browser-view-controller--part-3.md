<!-- leaf: implement-file/browser-view-controller--part-3 · source: file-browser-view-controller.md -->

# File Browser View Controller — continued (part 3)

## Design Decisions

**Decision**: Reuse an existing `FileTreeManager` for any root still present
across a `rebuildManagers()` call, rather than discarding and rebuilding
every manager from scratch.
**Rationale**: the source comment on `rebuildManagers()` states a scanned tree
should not be rescanned "because a *different* directory appeared" — a full
rebuild would re-run a filesystem scan and restart FSEvents watching for
every root, including ones that did not change.
**Approved**: pending.

**Decision**: Forward selection changes to `onPaneSelectionChange` through
`removeDuplicates().dropFirst().receive(on: RunLoop.main)` rather than a
plain synchronous `sink`.
**Rationale**: the source comment explains `@Published` publishes from
`willSet`, so a synchronous `sink` would read the *previous* selected node;
hopping to the run loop lets the store finish updating first,
`removeDuplicates` stops a re-click on the same row from re-firing, and
`dropFirst` discards the value `@Published` replays at subscription time so
a host is not told about a "change" that happened before it installed the
callback.
**Approved**: pending.

**Decision**: Normalize every root and every `GitStatusProvider.repoRoot`
comparison with `resolvingSymlinksInPath()`, not `standardizedFileURL`.
**Rationale**: the source comment (citing `ProjectCheckout.swift`) states an
injected provider's `repoRoot` is a resolved checkout directory while a root
handed to this controller may be an unresolved path the user picked; a
lexical comparison would silently fail whenever a symlink stands between
them, causing the pane to build a second, uninstrumented `GitStatusProvider`
without any visible error.
**Approved**: pending.

**Decision**: Look up the primary root's manager with a `preconditionFailure` on
miss, rather than an optional return or a freshly constructed fallback
manager.
**Rationale**: the source comment states `rebuildManagers()` runs in `init` and
always inserts the primary root, so a missing entry means an invariant broke
elsewhere; failing fast surfaces that bug immediately instead of papering
over it with a manager nothing else expects to exist.
**Approved**: pending.
