<!-- leaf: implement-git-client/projects-project-window-manager · source: git-client-projects-project-window-manager.md -->

# ProjectWindowManager

## Overview

`ProjectWindowManager` (`ProjectWindowManager.swift`) keeps one AppKit window
per open project, keyed by `git_repo.id` rather than by path, so opening "the
same project" twice after it has moved or been renamed still raises the same
window. For every project it opens it builds a matched pair — a
`ProjectController` that owns the checkout/tab reconciliation and a
`ComposableTabsWindowController` that hosts it — and tears both down together
when the window closes. It conforms to `ProjectOpening` so a
`ProjectsCoordinator` can hand it project-open/close requests, and to
`ObservableObject` so a browser can watch which projects are currently open.
Beyond the windows it opens itself, it can also adopt a window a host built by
some other means, so scripting can see it too, and it restores whichever
projects were flagged open when the app last quit. It is `@MainActor` and
holds no `Sendable` conformance of its own — every property and method is
confined to the main actor by that declaration alone.

