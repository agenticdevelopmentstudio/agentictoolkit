<!-- leaf: implement-git-client/projects-branch-controller--logging · source: git-client-projects-branch-controller.md -->

# BranchController

## Logging

`BranchController.swift` makes no logging call of its own — no `Logger`,
`os.Logger`, or `print` appears anywhere in the file. The one error this
file swallows (`refresh()`'s `catch`) is recorded by a different
component, `GitCommandLog` via `GitClient.execute`'s unconditional recording
(see `agentictoolkit://recipes/file-system-git`'s sibling `GitClient.swift`),
not logged a second time here.

| Event | Level | Message |
|-------|-------|---------|
| (none) | — | This file emits no log messages. |
