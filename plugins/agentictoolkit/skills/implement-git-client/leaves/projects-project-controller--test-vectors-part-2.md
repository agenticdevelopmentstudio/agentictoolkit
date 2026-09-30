<!-- leaf: implement-git-client/projects-project-controller--test-vectors-part-2 · source: git-client-projects-project-controller.md -->

# ProjectController — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-controller-020 | new-checkout-tabs-copy-arrangement-or-blueprint, active-tab-falls-back-to-first | Not present in `ProjectControllerTests.swift`; synthesized from `ProjectController.swift`. After `open()`, add a third worktree on disk, then call `await controller.refreshCheckouts()`. | The new worktree's tab record's `root` equals the existing arrangement copied with fresh node ids (`arrangement.inFreshIDs()`), not `workspace.layout.blueprint()`; `activeTabID` still names whichever tab was active before the refresh. |
| git-client-projects-project-controller-021 | checkouts-from-worktrees | Not present in `ProjectControllerTests.swift`; synthesized from `ProjectController.swift`. Build a `ProjectWorkspace` whose `directoryURL` is a plain directory that has never been a git repository (so `git worktree list --porcelain` there succeeds with empty output); call `await controller.open()`. | `checkouts == [ProjectCheckout(directory: workspace.directoryURL, branch: nil, isMain: true)]`; exactly one `BranchController` is created, for that synthetic checkout. |
