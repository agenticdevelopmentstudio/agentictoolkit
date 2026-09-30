<!-- leaf: implement-git-client/projects-projects-coordinator · source: git-client-projects-projects-coordinator.md -->

# ProjectsCoordinator

## Overview

`ProjectsCoordinator` is the project registry feature: one `ProjectDatabase`,
the in-memory list of known git repositories (`repos`), and the background
scan that keeps that list true to disk. Its own doc comment states the
model directly — "a 'project' here is a row, not a file," so a repository
can be renamed or moved on disk without losing its settings or window
layout (`ProjectsCoordinator.swift`). It is an `AppFeature`
(`AppFeature.swift`): the host constructs it once during launch, and it
registers two `AppCommand`s and two `MenuContribution`s on the caller's
`CommandRegistry` at `init` time so a palette, a shortcut, or an extension
can reach "Open Project…" and "Scan for Projects" by id. It owns none of
the scanning, reconciling, persisting, or window-presenting logic itself —
those are `GitRepoScanner`, `ProjectReconciler`, `ProjectDatabase`, and
`ProjectOpening`/`ProjectChooserWindow`/`ProjectScanProgressWindow`,
respectively (see their own recipes) — `ProjectsCoordinator` only sequences
calls to them and republishes the result through `repos` and
`didChangeNotification`.

