<!-- leaf: implement-git-client/projects-project-workspace--part-4 · source: git-client-projects-project-workspace.md -->

# ProjectWorkspace — continued (part 4)

## Design Decisions

**Decision**: `fileBrowserDirectoriesByPrimary` and `gitStatusProvidersByRoot`
hold their values weakly (`WeakCache`) instead of strongly.
**Rationale**: The doc comment on `WeakCache` states the failure mode this
avoids directly: holding values strongly meant a project "accumulated one
`FileBrowserDirectories` and one `GitStatusProvider` for every directory
anything had *ever* asked about — every worktree visited, every checkout
opened and closed again — for as long as the project stayed open," each one
"still observing a directory with nothing left on screen to show for it."
Weak values end an entry with its last holder without weakening the
invariant the cache exists for (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `gitStatusProvider(forDirectory:)` mints and caches its
`GitStatusProvider`s on `ProjectWorkspace`, not on `BranchController`.
**Rationale**: The doc comment explains the ordering bug this sidesteps: a
pane is built while the window installs its stored tabs, "before the first
`git worktree list` has returned and so before any `BranchController`
exists"; a provider resolved through the branch controllers "therefore
answered `nil` for every pane the window opened with," and because
`FileBrowserViewController` "latches what it is handed at init and never asks
again," those panes ran a private provider of their own for the rest of the
session while the `Refresh Status` command reached a different object.
Minting at the project level removes the ordering question rather than
moving it (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `projectDirectoriesDidChange(_:from:)` refreshes every other
live `FileBrowserDirectories` before returning, rather than letting each
browser reload lazily on its own next save.
**Rationale**: The doc comment states the bug this closes: each browser used
to write "the *whole* list back on any change," from its own stale snapshot,
so "the second one to save wrote its stale copy over the first one's addition
and the folder vanished from disk with no error." Refreshing every sibling
immediately, before anything else can save, keeps every open browser's copy
of the one project-wide list current (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `projectDirectoriesDidChange(_:from:)` re-adds `primary` to the
merged list when the stored list names it but the browser's own `urls` do
not.
**Rationale**: The doc comment explains why this merge is necessary: "an
object cannot represent its own primary" — a `FileBrowserDirectories` filters
its own primary out of `additional` because it is already shown and not
removable. If a user added a worktree's folder as an extra root of the main
checkout and then opened that worktree in its own tab, the worktree's own
browser would otherwise silently delete that entry on its next save
(`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `cacheDirectoryURL` is a pure computation that never creates the
directory it names.
**Rationale**: The doc comment states the reasoning directly: every caller so
far only names the folder (the file browser excludes it from the tree), and
"a getter that quietly makes a directory on disk … for every project, whether
or not anything ever caches into it … is a side effect nobody reading
`project.cacheDirectoryURL` would expect." Whoever writes there first creates
it (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: The `chrome.` prefix on `paneState`/`setPaneState` keys is
reserved by documentation only; `ProjectWorkspace` adds no runtime check that
a caller's key avoids it.
**Rationale**: The doc comment gives the reasoning: "Nothing checks this: the
prefix is what keeps chrome off content's keys, and this sentence is what
keeps content off chrome's. A check would have to let the one caller that is
*supposed* to write the prefix through, which buys less than the sentence
does." (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `setSetting(_:to:)` treats a `nil` value as a delete rather than
storing an empty or null row.
**Rationale**: The doc comment states this directly: "so 'never set' and 'set
back to the default' are the same state and neither accumulates"
(`ProjectWorkspace.swift`).
**Approved**: pending
