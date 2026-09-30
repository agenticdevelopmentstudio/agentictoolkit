<!-- leaf: implement-git-client/projects-projects-coordinator--logging · source: git-client-projects-projects-coordinator.md -->

# ProjectsCoordinator

## Logging

`ProjectsCoordinator` conforms to `Loggable` (`ProjectsCoordinator.swift`); subsystem defaults to `Bundle.main.bundleIdentifier`,
category is `ProjectsCoordinator`.

| Event | Level | Message |
|-------|-------|---------|
| `rename`'s `database.update` failed | error | `Rename failed for <repoID.uuidString>: <error>` |
| `openProject`'s `database.markOpened` failed | error | `Could not record open time: <error>` |
| `finishScan` insert failed | error | `Could not add <repo.path>: <error>` |
| `finishScan` update failed | error | `Could not update <repo.path>: <error>` |
| `finishScan` delete failed | error | `Could not remove <repo.path>: <error>` |
| `finishScan` completed | info | `Scan complete: <summary.summaryText>` |

`init`'s and `reload()`'s failed `database.allRepos()` reads, and `stop()`'s
failed `database.checkpoint()`, make no log call at all — see
**database-read-failure-unsignaled** and
**stop-checkpoint-failure-unsignaled**.
