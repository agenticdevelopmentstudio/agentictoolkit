<!-- leaf: implement-git-client/projects-project-controller--logging · source: git-client-projects-project-controller.md -->

# ProjectController

## Logging

`ProjectController.swift` makes one logging call of its own, through its
`Loggable` conformance (`ProjectController.swift`): `readCheckouts()`'s
`catch` block, on a failed `gitClient.worktrees(in:)` call
(`ProjectController.swift`). Subsystem defaults to
`Bundle.main.bundleIdentifier`; category is `ProjectController`.

| Event | Level | Message |
|-------|-------|---------|
| `gitClient.worktrees(in:)` threw | error | `readCheckouts: worktrees(in:) failed for <directory>; keeping last checkouts` |
