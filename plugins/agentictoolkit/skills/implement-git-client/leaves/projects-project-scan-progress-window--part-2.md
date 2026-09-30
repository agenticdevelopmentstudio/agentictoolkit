<!-- leaf: implement-git-client/projects-project-scan-progress-window--part-2 · source: git-client-projects-project-scan-progress-window.md -->

# ProjectScanProgressWindow — continued (part 2)

## Design Decisions

**Decision**: The panel reports no per-directory counts and no scanned path,
only the fixed strings "Scanning for projects…" and "Scan complete".
**Rationale**: The type's doc comment states the counts were "registry
bookkeeping the user had not asked for and could not act on," and the path
"flickered through was unreadable at the speed the walk produces it"
(`ProjectScanProgressWindow.swift`).
**Approved**: pending

**Decision**: The panel is not presented modally.
**Rationale**: The doc comment states "the scan touches nothing the user
could be editing, so blocking them out of the app would buy nothing"
(`ProjectScanProgressWindow.swift`).
**Approved**: pending

**Decision**: The panel provides no Cancel control.
**Rationale**: The doc comment states "a Cancel button that leaves the
registry half-reconciled is worse than a scan that finishes"
(`ProjectScanProgressWindow.swift`).
**Approved**: pending

**Decision**: `present()` orders the window front without making it key
(`orderFrontRegardless()` rather than `makeKeyAndOrderFront`), and
`becomesKeyOnlyIfNeeded` is set to `true`.
**Rationale**: The doc comment on `present()` states this is "so a scan at
launch does not steal focus from whatever the user is already doing"
(`ProjectScanProgressWindow.swift`).
**Approved**: pending

**Decision**: `finish()` leaves the bar at its full determinate value rather
than leaving it indeterminate or resetting it to empty.
**Rationale**: The doc comment on `finish()` states "an indeterminate bar
frozen part-way through reads as a scan that gave up"
(`ProjectScanProgressWindow.swift`).
**Approved**: pending

**Decision**: The `asyncAfter` closure in `finish()` captures `self`
strongly rather than weakly.
**Rationale**: The inline comment states this directly: the caller "drops
its reference as soon as it has asked for the finish, so a weak capture
leaves nothing alive to run `close()` and the panel stays on screen for
good" (`ProjectScanProgressWindow.swift`), which matches
`ProjectsCoordinator.swift` setting `progressWindow = nil` immediately after
calling `finish()` (`ProjectsCoordinator.swift`).
**Approved**: pending
