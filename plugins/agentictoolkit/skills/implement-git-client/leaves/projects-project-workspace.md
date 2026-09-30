<!-- leaf: implement-git-client/projects-project-workspace · source: git-client-projects-project-workspace.md -->

# ProjectWorkspace

## Overview

`ProjectWorkspace` (`ProjectWorkspace.swift`) is one open project: the `GitRepo`
it is, the `ProjectDatabase` rows keyed to that repository, and the tab/split
arrangement its window shows. Per its own doc comment, it is "what `NSDocument`
used to be here, minus the document" — there is no file to read, write,
autosave, revert or name, because a project is a `git_repo` row plus the rows
keyed to it, so every edit is already saved and a repository can move on disk
without the project noticing. It owns the project's stored tab tree
(`storedTabs()`, `initialTabs()`, `persistTabs(...)`), an untyped per-pane and
per-project string bag (`paneState`/`setPaneState`, `setting`/`setSetting`),
the project's extra file-browser roots (`fileBrowserDirectories(primary:)`,
`persistProjectDirectories(...)`), and two directory-keyed object caches —
`FileBrowserDirectories` and `GitStatusProvider` — that hold their values
weakly so exactly one instance exists for as long as anything still needs it.
It is `@MainActor` and holds no `Sendable` conformance of its own; every
property and method is confined to the main actor by that declaration alone.

