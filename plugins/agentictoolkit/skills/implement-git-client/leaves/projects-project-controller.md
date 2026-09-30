<!-- leaf: implement-git-client/projects-project-controller · source: git-client-projects-project-controller.md -->

# ProjectController

## Overview

`ProjectController` (`ProjectController.swift`) is the one-per-project-window
owner of a project's `ProjectCheckout`s and their `BranchController`s. It
decides which tabs the window shows by reconciling the checkouts git reports
against the tabs `ProjectWorkspace` has stored, and it answers the window
controller's tab-item requests as a `ComposableTabsTabItemDataSource`. Per its
own doc comment, it "knows nothing about views beyond vending what a branch
controller makes." It serializes its own two entry points (`open()`,
`refreshCheckouts()`) onto one chained `Task` so two overlapping callers
cannot let a slower, earlier git read overwrite a faster, later one, and it
keeps a project's branch-scoped `AppCommand`s registered with the app's
`CommandRegistry` in step with which checkouts currently exist. It is
`@MainActor` and holds no `Sendable` conformance of its own — every property
and method is confined to the main actor by that declaration alone.

