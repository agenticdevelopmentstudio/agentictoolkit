<!-- leaf: implement-git-client/scripting--logging · source: git-client-scripting.md -->

# GitClientScripting

## Logging

`ProjectWindowManager+Scripting.swift` and the three wrapper types make no
logging call — no `Logger`, `os.Logger`, or `print` appears in any of the
four files. A branch that fails to resolve is not logged here at all; any
underlying git failure is recorded once, upstream, in `GitCommandLog` via
`GitClient.execute` (see `agentictoolkit://recipes/git-client-projects-branch-controller`),
not a second time by this extension.

| Event | Level | Message |
|-------|-------|---------|
| (none) | — | This file and its three wrapper types emit no log messages. |
