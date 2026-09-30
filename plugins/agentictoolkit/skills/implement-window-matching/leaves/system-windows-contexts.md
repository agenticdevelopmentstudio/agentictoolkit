<!-- leaf: implement-window-matching/system-windows-contexts · source: window-matching-system-windows-contexts.md -->

# Window Matching System Windows Contexts

## Overview

The contexts slice of AgenticToolkit's system-window feature groups other applications' windows into named **contexts** (workspaces such as "iOS App" or "Docs") and switches between them by moving every window that does not belong to the target context off-screen ("parking") and moving the target context's windows back to their saved frames. It is seven files:

- `Core/SystemWindows/Contexts/SystemWindowContextsState.swift`: `SystemWindowContextsState`, the persisted top-level record (active context ID and ordered context IDs).
- `Core/SystemWindows/Contexts/SystemWindowContextStore.swift`: `SystemWindowContextStore`, which reads and writes that state and one JSON file per `SystemWindowContext` under a caller-supplied root directory, serializing writes with an `flock(2)` lock file. It also declares `SystemWindowContextStoreError`.
- `Core/SystemWindows/Contexts/SystemWindowContextsSettings.swift`: `SystemWindowContextsSettings` (user-facing settings persisted by the host through `UserSettings`) and the `ReconcileBehavior` enum.
- `Core/SystemWindows/Contexts/ReconcileModels.swift`: `ReconcileItem` and `ReconcileCandidate`, value types a Reconcile UI lists after relaunch.
- `CoreMacOS/SystemWindows/Contexts/SystemWindowContextError.swift`: `SystemWindowContextError`, the manager's error enum.
- `CoreMacOS/SystemWindows/Contexts/SystemWindowContextManager.swift`: `SystemWindowContextManager`, the `@MainActor` engine that owns the contexts, parks and restores windows through an injected `SystemWindowControlling`, re-matches dormant window snapshots by fingerprint through `SystemWindowMatcher`, manages custom heuristic rules through `CustomHeuristicStore`, and persists after every mutation.
- `CoreMacOS/SystemWindows/Contexts/SystemWindowContextsModel.swift`: `SystemWindowContextsModel`, an `@MainActor` `ObservableObject` that wraps the manager for SwiftUI, turns thrown errors into a `lastError` string, drives launch reconciliation, receives window-lifecycle events as the `SystemWindowObserverDelegate`, and persists settings. It also declares `SystemWindowContextsConfiguration`, the host's injected branding and defaults.

The data types these files operate on, `SystemWindowContext` and `SystemWindowSnapshot` (in `Core/SystemWindows/`), the matcher `SystemWindowMatcher` (whose `autoAssignThreshold` is `80`), and the window controller protocol `SystemWindowControlling` live outside this slice and are referenced by name. A window is **live** when its snapshot's `windowID` is non-nil and **dormant** when it is nil (`SystemWindowSnapshot.isLive`); a dormant snapshot keeps its fingerprint so it can be re-attached. Use this ingredient when an app needs persistent, switchable groups of third-party windows that survive the app quitting, the owning apps quitting, and a reboot that recycles window IDs.

