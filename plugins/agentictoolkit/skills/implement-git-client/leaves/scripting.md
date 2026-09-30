<!-- leaf: implement-git-client/scripting · source: git-client-scripting.md -->

# GitClientScripting

## Overview

`ProjectWindowManager+Scripting.swift` is the extension on `ProjectWindowManager`
that answers everything Cocoa Scripting (AppleScript) asks about project
windows, tabs and panes: three enumerated arrays (`scriptableProjectWindows`,
`scriptableProjectTabs`, `scriptablePanes`) and three id-based lookups
(`scriptableProjectWindow(uniqueID:)`, `scriptableProjectTab(uniqueID:)`,
`scriptablePane(uniqueID:)`). It hangs off `ProjectWindowManager` rather than a
separate registry because that manager is already the answer to "which
project windows are open." Its one piece of domain logic beyond enumeration is
git: `scriptingTabs(of:)` resolves each tab's working directory to a live
branch name by reaching through `ProjectController.branchController(forDirectory:)`
into that checkout's `BranchController.currentBranch` — the "git client" a
project tab's `branch` property exposes to a script. The extension itself
constructs three `NSObject`-backed wrapper types it does not define —
`ScriptableProjectWindow`, `ScriptableProjectTab` and `ScriptablePane` — whose
own properties this recipe also specifies, because no other recipe yet owns
them.

