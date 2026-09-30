<!-- leaf: implement-git-client/projects-project-workspace--logging · source: git-client-projects-project-workspace.md -->

# ProjectWorkspace

## Logging

Subsystem: `Bundle.main.bundleIdentifier` | Category: `ProjectWorkspace`
(`ProjectWorkspace.swift`, via `Loggable`).

| Event | Level | Message |
|-------|-------|---------|
| `database.saveTabs` threw | error | `Failed to save project tabs: <error description>` |
| `database.paneState` threw (via `logPaneStateFailure("load", ...)`) | error | `Failed to load pane state (repo <repo id>, node <node id>, key <key>): <error description>` |
| `database.setPaneState` threw (via `logPaneStateFailure("save", ...)`) | error | `Failed to save pane state (repo <repo id>, node <node id>, key <key>): <error description>` |
| `database.pruneNestedPaneState` threw (via `logPaneStateFailure("prune", ...)`, key `"*"`) | error | `Failed to prune pane state (repo <repo id>, node <node id>, key *): <error description>` |
| `database.setting` threw | error | `Failed to load project setting: <error description>` |
| `database.setSetting` threw | error | `Failed to save project setting: <error description>` |
| `database.loadProjectDirectories` threw | error | `Failed to load project directories: <error description>` |
| `database.saveProjectDirectories` threw | error | `Failed to save project directories: <error description>` |

`database.loadTabs` throwing inside `storedTabs()` produces no log line at
all — see the open question on stored-tabs-load-failure-signal.
