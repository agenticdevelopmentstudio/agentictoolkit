<!-- leaf: implement-git-client/projects-project-window-manager--part-4 · source: git-client-projects-project-window-manager.md -->

# ProjectWindowManager — continued (part 4)

## Design Decisions

**Decision**: `openProject(_:)` calls `refreshOpenWorkspaceIDs()` — and
therefore `onOpenProjectsChanged?()` — only after the window has been
registered, ordered to the front, and offered app activation, not at the
point the controller is first added to `controllers`.
**Rationale**: The doc comment explains the bug this fixes directly: firing
earlier "published 'the open set changed' while `NSApp` still described the
previous window," so `frontWindowController`-derived seams like the extension
hosts' `workspaceRoots` ran "against the *old* project's roots, or against
none at all on the first project of the session, and never ran again"
(`ProjectWindowManager.swift`).
**Approved**: pending

**Decision**: The per-controller callbacks `openProject(_:)` assigns
(`onTabsDidChange`, `onTabItemsNeedRefresh`) capture `self`, `controller`, and
`projectController` weakly and re-check `self.projectControllers[repo.id]
=== projectController` before touching the window.
**Rationale**: Labeled "Ruling Q" in the source: the guard exists so "a
controller that was closed and replaced — or one whose window is already gone
— can never drive a window that is no longer its own".
**Approved**: pending

**Decision**: `observeClose(of:repoID:recordsOpenState:)` registers its
`NSWindow.willCloseNotification` observer with `queue: nil` rather than
`.main`.
**Rationale**: The inline comment states the failure mode a `.main`-queued
(enqueued) delivery would allow: "the scan closes a deleted project's window
and then deletes its row in the same turn, and a block that lands after that
deletes-then-writes — a foreign key that no longer resolves." `queue: nil`
keeps the handler on the poster's thread, in the same run-loop turn as the
close.
**Approved**: pending

**Decision**: The close handler skips `setWindowOpen(false, repoID:)` when
`WindowManager.shared.isTerminating` is `true`.
**Rationale**: The inline comment states the reason directly: "AppKit closes
still-open windows on the way out of the app. Recording that as 'the user
closed it' would stop every open project from reopening next launch, which is
the opposite of what quitting with windows open means".
**Approved**: pending

**Decision**: The close handler captures the outgoing `ProjectController`
and/or `languageServices` before removing the project from `controllers`, and
routes the scheduled teardown through the captured `ProjectController
.shutdown()` when one exists, falling back to the captured `languageServices
.shutdown()` only when it does not — never both.
**Rationale**: `ProjectController.shutdown()` and the inline
`languageServices.shutdown()` path both end at the same
`languageServices.shutdown()` call; running both "would shut the same
services down twice." The inline fallback exists only for a window
`adoptForScripting(_:)` registered, which has no project controller of its
own to route through.
**Approved**: pending

**Decision**: `shutdownAllLanguageServices()` hands every started-but-not-yet-
finished teardown to `PendingTeardowns` rather than starting a bare, unheld
`Task` at each window close.
**Rationale**: `PendingTeardowns`' own doc comment names the two independent
near-misses this extraction fixes — this type's window-close observer and
`LanguageServerRegistry.reconcile` both started detached teardown work and
"the app-level quit path... enumerated a collection the work had already
left, found nothing to wait for, and returned," orphaning a subprocess when
the process then exited inside `SubprocessChannel.terminate()`'s roughly
2.5-second budget (`PendingTeardowns.swift`, class doc comment;
`ProjectWindowManager.swift`).
**Approved**: pending
