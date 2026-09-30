<!-- leaf: implement-git-client/projects-project-database-layout · source: git-client-projects-project-database-layout.md -->

# ProjectDatabase+Layout

## Overview

`ProjectDatabase+Layout.swift` is a `ProjectDatabase` extension that persists everything a project window's tab-and-pane arrangement needs to survive a relaunch: the tabs docked to each edge, the split tree of panes inside each tab, per-pane UI state (sizes, expansion, selection — whatever a caller stores under a string key), and the extra directories a project's file browser shows beyond the repository root. `ProjectDatabase` itself (`ProjectDatabase.swift`) owns the SQLite connection, the schema migrations that create the five tables this extension reads and writes (`project_tabs`, `layout_nodes`, `project_state`, `pane_state`, `project_directories`), and the low-level `execute`/`executeBound`/`forEachRow` helpers this extension calls; this extension adds no schema and no connection state of its own — it is purely a set of methods layered onto the base class.

Every row this extension touches is scoped to one `repo_id`, matching a `git_repo.id` row owned by `ProjectDatabase`'s core methods; nothing here reads or writes a row for any `repoID` other than the one a caller passes in. `ProjectDatabase` is a `public final class` with no `Sendable` conformance and no `actor`/`@MainActor` isolation (`ProjectDatabase.swift`), so this extension's methods carry no concurrency guarantee of their own — they run wherever the caller runs, synchronously, against one shared SQLite connection.

