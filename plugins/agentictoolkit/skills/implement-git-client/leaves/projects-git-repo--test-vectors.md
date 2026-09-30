<!-- leaf: implement-git-client/projects-git-repo--test-vectors · source: git-client-projects-git-repo.md -->

# GitRepo

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-git-repo-001 | git-repo-url-is-directory | `GitRepo(path: "/tmp/example", name: "example").url` | A file URL whose `path` is `/tmp/example` and whose `hasDirectoryPath` is `true`, regardless of whether `/tmp/example` exists. |
| git-client-projects-git-repo-002 | git-repo-default-name-from-path | `GitRepo.defaultName(forPath: "/Users/x/Projects/myrepo")` | Returns `"myrepo"`. |
| git-client-projects-git-repo-003 | scanned-git-repo-leaf-name | `GitRepoScannerTests.swift`: scan a directory named `alpha` containing a valid `.git`, then read `found.first?.leafName`. | Returns `"alpha"`. |
| git-client-projects-git-repo-004 | scan-summary-text-headline-pluralization, scan-summary-text-joining | `ProjectReconcilerTests.swift` (`testAQuietScanSaysSo`): a plan whose summary has `unchanged: 1` and every other count `0`. | `plan.summary.summaryText == "1 project, no changes"`. |
| git-client-projects-git-repo-005 | scan-summary-text-part-selection, scan-summary-text-joining | `ProjectReconcilerTests.swift` (`testTheSummaryCountsEveryRepoExactlyOnce`): a plan whose summary has `added: 1`, `moved: 1`, `removed: 1`, `unchanged: 1`. | `plan.summary.summaryText == "3 projects — 1 new, 1 moved, 1 removed"` (the one `unchanged` project is counted in `found` but never named). |
| git-client-projects-git-repo-006 | scan-summary-found-excludes-removed, scan-summary-text-part-selection | A `ProjectScanSummary` with `removed = 5` and every other count `0`. | `found == 0` and `summaryText == "0 projects — 5 removed"`. |
| git-client-projects-git-repo-007 | git-repo-structural-equatable | Two `GitRepo` values built with the same `id`, `path`, and `name`, but `firstSeen`/`lastSeen` passed as two different `Date` values. | The two values compare unequal with `==`. |
| git-client-projects-git-repo-008 | git-repo-default-id-generation, git-repo-default-timestamps | `GitRepo(path: "/tmp/a", name: "a")` constructed twice in immediate succession. | Each call produces a distinct `id`; the two values are unequal even though `path` and `name` match. |
| git-client-projects-git-repo-009 | scanned-git-repo-remote-required | Attempt to write `ScannedGitRepo(path: "/tmp/a")` with no `remote` argument. | Does not compile — `remote` has no default value, unlike `GitRepo.remote`. |
