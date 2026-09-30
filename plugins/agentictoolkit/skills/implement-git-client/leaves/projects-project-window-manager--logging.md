<!-- leaf: implement-git-client/projects-project-window-manager--logging · source: git-client-projects-project-window-manager.md -->

# ProjectWindowManager

## Logging

`ProjectWindowManager.swift` makes five logging calls, through its `Loggable`
conformance. Subsystem defaults to
`Bundle.main.bundleIdentifier`; category is `ProjectWindowManager`.

| Event | Level | Message |
|-------|-------|---------|
| `coordinator?.database` is `nil` in `openProject(_:)` | error | `Cannot open <repo.name>: no project database attached` |
| `languageServicesFactory` is `nil` or returns `nil` | info | `No language services for <repo.name>: no factory wired` |
| A flagged-open repo's folder is missing at restore | info | `Not reopening <repo.name>: its folder is gone` |
| `database.setting(repoID:key:)` throws in `isWindowOpen(repoID:)` | error | `Could not read window state for <repoID>: <error>` |
| `database.setSetting(repoID:key:value:)` throws in `setWindowOpen(_:repoID:)` | error | `Could not record window state for <repoID>: <error>` |
