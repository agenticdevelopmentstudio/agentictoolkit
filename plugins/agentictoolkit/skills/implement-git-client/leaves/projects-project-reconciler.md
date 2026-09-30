<!-- leaf: implement-git-client/projects-project-reconciler · source: git-client-projects-project-reconciler.md -->

# ProjectReconciler

## Overview

`ProjectReconciler` is a stateless namespace of static functions that turns
"what a directory scan just found" plus "what the registry already knew"
into the rows a caller should write. Its one entry point, `plan(existing:scanned:now:isStillARepository:)`,
matches each `ScannedGitRepo` a scan produced against the `GitRepo` rows
already known, in a fixed order: exact path matches first, then unresolved
rows are checked against disk to tell "not reported" apart from "genuinely
gone," then a move pass matches a relocated repository by remote and, failing
that, by directory name, then whatever is still unclaimed becomes a new
insert, and whatever is still unaccounted for becomes a delete. The doc
comment on the type states it is "Pure and `nonisolated`" so that "the
interesting half of scanning" can be tested without a database, a filesystem,
or a main actor (`ProjectReconciler.swift`). Nothing in this file
performs I/O beyond the injectable `isStillARepository` check; reading the
scan results off disk is `GitRepoScanner`'s job (see the
`git-client-projects-git-repo-scanner` recipe), and writing the resulting
`Plan` to a database is a separate caller's job.

