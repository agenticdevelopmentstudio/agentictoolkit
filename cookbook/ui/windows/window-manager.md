---
id: 61c7b509-78d1-4407-9a4e-25b155f06fbb
title: Window Manager
domain: agentictoolkit://cookbook/ui/windows/window-manager
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A coordinator for window frame and visibility persistence, the
  live window registry, launch restore, and document recents.
platforms:
- swift
- macos
tags:
- window-management
- persistence
- recents
depends-on:
- agentictoolkit://cookbook/foundation/settings-storage
- agentictoolkit://cookbook/ui/windows/screen-manager
- agentictoolkit://cookbook/ui/windows/single-window-controller
related:
- agentictoolkit://cookbook/ui/windows/window-recents
references: []
approved-by: ''
approved-date: ''
---

# Window Manager

## Overview

The window manager is the top-level coordinator for the toolkit's window
infrastructure. It owns:

- a frame manager that persists window frames and visibility and reacts to
  screen changes (specified by the frame-manager and
  [the screen manager](agentictoolkit://cookbook/ui/windows/screen-manager)
  recipes);
- a window registry that looks up live instances of
  [the single-instance window base](agentictoolkit://cookbook/ui/windows/single-window-controller)
  by window id through weak references;
- the launch-restore pass (registering a restorable id and factory, running
  the launch-restore pass, reopening recents on launch);
- document recents recording (recording a show/close interaction) and the
  mirror of the recent-windows-count setting into the platform's
  recent-documents limit;
- an app-termination latch that lets the single-instance window base tell a
  user close from a quit close.

The recipe also covers the persistence layer it is built on: the
window-state storage protocol, its two implementations (the
settings-store-backed backend, the default, and the platform-preferences
backend), the window-state namespace key prefix that lets two copies of one
app keep separate layouts, and the window screenshot own-window capture
utility that lives alongside it.

Production code uses the shared window manager; tests construct an isolated
instance with a mock screen provider, in-memory storage, and an isolated
screen manager.

## Behavioral Requirements

### Isolation and ownership

- **single-thread-isolation**: The window manager, the window registry, the
  window-state storage protocol, and the settings-store-backed storage
  backend MUST be confined to a single designated thread; every operation
  on them MUST run on it.
- **namespace-thread-safety**: The window-state namespace MUST be callable
  from any thread; its current prefix MUST be guarded by a lock rather than
  by thread confinement.
- **screenshot-isolation**: The own-window-capture operation MUST be
  callable from any thread, and the write-PNG operation MUST run on the
  window manager's single designated thread.
- **shared-instance**: The shared window manager MUST be a single
  process-wide instance built with the shared screen manager.
- **single-screen-manager**: A window manager constructed without an
  explicit screen manager MUST use the shared screen manager, never a newly
  created one, so exactly one instance owns the persisted screen-set list
  and the screen-change observer.
- **frames-ownership**: Each window manager MUST create exactly one frame
  manager from its screen provider, storage, and screen manager, and expose
  it.
- **registry-ownership**: Each window manager MUST create exactly one empty
  window registry and expose it.
- **self-registration-target**: The single-instance window base MUST
  register itself with the shared window manager's registry during its
  initializer; a separately constructed window manager's registry is
  populated only by explicit registration calls.

### Initialization side effects

- **recent-limit-on-init**: The initializer MUST write the current value of
  the recent-windows-count setting to the platform's recent-documents limit
  setting before returning.
- **recent-limit-mirror**: After initialization, every change to the
  recent-windows-count setting MUST be re-applied to the platform's
  recent-documents limit setting, delivered on the main run loop.
- **recent-limit-weak-capture**: The settings subscription MUST hold the
  manager weakly, so it does not keep the manager alive.
- **termination-observer**: The initializer MUST subscribe to the
  platform's app-termination notification from any sender.

### Termination latch

- **terminating-default**: The termination flag MUST be false after
  initialization.
- **terminating-latch**: When the app-termination notification is posted,
  the termination flag MUST become true.
- **terminating-one-way**: The manager MUST NOT reset the termination flag
  to false on its own; only module-internal code (tests) can write it.
- **terminating-consumer**: The single-instance window base's
  window-will-close callback MUST skip persisting a hidden visibility state
  while the shared window manager's termination flag is true, and MUST
  persist it when the flag is false.

### Recents recording

- **interaction-kinds**: The interaction kind MUST have exactly two values,
  "show" and "close", and MUST be safe to pass across concurrency domains.
- **close-ignored**: Recording an interaction with kind "close" MUST have
  no effect.
- **spec-gate**: Recording an interaction with kind "show" MUST have no
  effect when the controller has no registered spec or when the spec's
  behavior does not include "include in recents".
- **document-recent**: Recording a "show" interaction, for a controller
  with a spec that includes "include in recents" and a non-nil document
  URL, MUST pass that URL to the platform's recent-documents API.
- **non-document-recents-noop**: A non-document window (no document URL)
  that passes the spec gate MUST NOT be recorded anywhere; the source
  states single-window tracking "lands in a follow-up slice with a
  dedicated recents tracker".
- **document-url**: The single-instance window base's document-URL
  accessor MUST return the file URL of the controller's document when the
  document is a platform document, and nothing otherwise.

### Recent-document limit

- **recent-limit-write**: Applying the recent-document count from settings
  MUST write the current value of the recent-windows-count setting,
  unchanged and unvalidated, to the platform's recent-documents limit
  setting.
- **recent-limit-default**: The recent-windows-count setting MUST default
  to 10.

### Launch restore

- **register-restorable**: Registering a restorable id MUST store the
  factory under the id, replacing any factory previously stored under the
  same id, and MUST NOT call the factory.
- **restore-builds-all**: The launch-restore pass MUST call every
  registered factory exactly once per invocation, in unspecified order.
- **restore-visibility-pass**: After running the factories, the
  launch-restore pass MUST run the visibility-restore step on the live
  controller for every id in the registry's registered ids.
- **restore-visibility-rule**: The visibility-restore step MUST show the
  window only when the controller's spec persists visibility and the last
  persisted visibility for its window id is exactly true; a persisted false
  or no persisted value MUST leave it closed.
- **restore-missing-factory-log**: For each id reported by the storage's
  visible-window-ids operation that has neither a registered factory nor a
  live registry controller, the launch-restore pass MUST log one error
  `restoreOnLaunch: visible window '<id>' has no registered factory` with
  the id marked public.
- **restore-then-reopen**: The launch-restore pass MUST run the
  reopen-recents step after the visibility pass and the missing-factory
  check.
- **restore-reentrant**: The launch-restore pass MAY be called again (the
  source recommends it on reactivation, such as a second-launch distributed
  notification); each call reruns every factory and the full pass.
- **visible-ids-default**: Storage that does not implement the
  visible-window-ids operation MUST report an empty list.
- **visible-ids-settings-store**: NEEDS REVIEW: Not implemented in source.
  The settings-store-backed storage backend, the default storage of the
  window manager and the shared window manager, does not implement the
  visible-window-ids operation, so it inherits the empty default, and the
  missing-factory error declared by the storage protocol's doc comment
  ("Lets the launch-restore pass detect a window that was visible but has
  no registered factory") never fires in the default configuration;
  settling it needs either a key-enumeration API on the settings store or
  an explicit statement that the check applies only to the
  platform-preferences backend.

### Reopen on launch

- **reopen-no-app**: The reopen-recents step MUST return without effect
  when no app instance exists.
- **reopen-policy**: The decision MUST follow the reopen-on-launch-policy
  setting: "match the system setting" returns the system default, "always"
  returns true, and "never" returns false.
- **reopen-policy-default**: The reopen-on-launch-policy setting MUST
  default to "match the system setting".
- **reopen-system-default**: The system default MUST be the boolean value
  of the platform's system-wide reopen-windows-on-quit default, reading
  false when the key is absent.
- **reopen-disabled-closes**: When the decision is not to reopen, the
  method MUST close, through its window controller, every app window whose
  window controller has a non-nil document, and MUST open nothing.
- **reopen-disabled-keeps-others**: When the decision is not to reopen,
  windows without a window controller or whose controller has no document
  MUST be left open.
- **reopen-enabled-opens-recents**: When the decision is to reopen, the
  method MUST request that the platform document controller open, with
  display requested, every URL in the platform's list of recent document
  URLs that is not already the file URL of an open window's document.
- **reopen-all-recents**: When the decision is to reopen, the method MUST
  open every recent URL, not only the documents that were open when the app
  last quit; whether a window spec allows reopening on launch is not
  consulted.
- **reopen-open-failure**: NEEDS REVIEW: Not implemented in source. The
  open-recent completion handler is empty, so a recent document that fails
  to open (moved, deleted, unreadable) produces no log, no user-facing
  error, and no removal from recents; settling it needs a decision on
  whether failures are logged, presented, or pruned.

### Window registry

- **registry-register**: Registering a controller MUST store a weak
  reference to it under its window id, replacing any prior entry for that
  id.
- **registry-empty-id**: Registering a controller MUST ignore one whose
  window id is the empty string.
- **registry-lookup**: Looking a controller up by id MUST return the live
  controller registered under it, or nothing when none was registered or
  the registered controller has been deallocated.
- **registry-registered-ids**: The registered-ids list MUST name every
  registered controller that is still alive, whether or not its window is
  open, in unspecified order.
- **registry-visible-ids**: The visible-ids list MUST name registered,
  alive controllers whose visibility flag is true, in unspecified order.
- **registry-has-visible**: The has-visible-window flag MUST be true
  exactly when at least one registered, alive controller has its visibility
  flag true.
- **registry-single-visibility-definition**: The visible-ids list and the
  has-visible-window flag MUST use the same visibility test.
- **registry-no-pruning**: Entries for deallocated controllers MUST remain
  in storage until the same id is re-registered; they are filtered out of
  every read.

### Window state storage

- **storage-protocol**: The window-state storage protocol MUST provide
  operations to load state, save state, remove state, load visibility, save
  visibility, remove visibility, and list visible window ids, all keyed by
  window id string.
- **storage-independent-keys**: Frame state and visibility MUST be stored
  under separate keys so a window can persist one without the other.
- **storage-key-format**: The frame key MUST be the current namespace
  prefix plus the state-key prefix plus the id, and the visibility key MUST
  be the current namespace prefix plus the visibility-key prefix plus the
  id.
- **storage-key-defaults**: The state-key prefix MUST default to
  `WindowState_` and the visibility-key prefix MUST default to
  `WindowVisible_` in both implementations.
- **storage-namespace-late-binding**: Both implementations MUST read the
  namespace when composing each key, not at construction, so a namespace
  set after a storage was created applies to it.
- **storage-state-json**: The persisted window state MUST be stored as
  JSON-encoded data in both implementations, so either implementation reads
  state the other wrote over the same underlying store.
- **storage-visibility-native**: Visibility MUST be stored as a native
  boolean (not JSON) in both implementations.
- **storage-visibility-tristate**: Loading visibility MUST return nothing
  when the key has never been written, and the stored boolean otherwise, so
  "never shown" is distinct from "explicitly hidden".
- **storage-remove**: Removing state and removing visibility MUST delete
  the key, after which the matching load returns nothing.
- **userdefaults-target**: The platform-preferences storage backend MUST
  read and write the platform's local preferences store directly, bypassing
  the settings store.
- **userdefaults-visible-ids**: The platform-preferences storage backend's
  visible-window-ids operation MUST return, in unspecified order, the id
  suffix of every key in that store that starts with the current namespace
  prefix plus the visibility-key prefix and whose value is the boolean
  true.
- **settings-store-target**: The settings-store-backed storage backend
  MUST route every key through its injected settings store with secure
  storage turned off, so values land in the store's non-secure provider.
- **settings-store-change-signal**: Writes and removals through the
  settings-store-backed storage backend MUST emit the key name on the
  store's change-notification stream when the provider emits one (the
  platform-preferences provider does); the platform-preferences storage
  backend emits nothing.
- **settings-store-non-bool-visibility**: When a visibility key exists but
  does not hold a boolean, the settings-store-backed storage backend's
  load-visibility operation MUST return false (the setting's default),
  whereas the platform-preferences storage backend returns nothing.
- **storage-codec-failure**: NEEDS REVIEW: Not implemented in source. In
  both implementations a persisted window state that fails to encode is
  silently not written, and stored data that fails to decode reads as
  absent (never saved), with no log or error to the caller; settling it
  needs a decision on whether codec failures are logged or surfaced.

### Namespace

- **namespace-default**: The current namespace prefix MUST be the empty
  string until a host sets a namespace, so un-namespaced keys match the
  existing on-disk format.
- **namespace-qualify**: Qualifying a key MUST return the current prefix
  concatenated with the key.
- **namespace-token**: Isolating to a path MUST set the current prefix to
  "Instance" plus the lowercase hex of the first 4 bytes of the SHA-256
  digest of the path's UTF-8 bytes plus "_" (8 hex characters).
- **namespace-stable**: Isolating to a path MUST produce the same prefix
  for the same path on every call and launch.
- **namespace-no-raw-path**: The prefix MUST NOT contain any substring of
  the path.
- **namespace-bundle**: Isolating to the running bundle MUST isolate to the
  bundle's standardized bundle-location path, defaulting to the main
  bundle.
- **namespace-reset**: Resetting the namespace MUST set the current prefix
  back to the empty string.
- **namespace-host-timing**: A host that wants isolation MUST isolate to
  the running bundle before it first touches the window manager (per the
  type's doc comment); keys written earlier stay under the previous
  prefix.

### Window screenshot

- **screenshot-capture**: The own-window-capture operation MUST return a
  captured image of the given window, requesting full window bounds
  without extra frame chrome, at the display's best available resolution,
  over a null rectangle, or nothing when the capture fails.
- **screenshot-symbol-missing**: When the platform's window-list image
  capture facility cannot be resolved at runtime, the own-window-capture
  operation MUST return nothing rather than crash.
- **screenshot-symbol-once**: The facility MUST be resolved at most once
  per process.
- **screenshot-no-permission**: Own-window capture MUST NOT require or
  request Screen Recording permission.
- **screenshot-png-offscreen**: The write-PNG operation MUST return false
  and write nothing when the window is not currently on screen (its
  platform on-screen handle is not positive).
- **screenshot-png-failure**: The write-PNG operation MUST return false
  when capture, PNG encoding, or the file write fails.
- **screenshot-png-success**: The write-PNG operation MUST write PNG data
  to the URL and return true when every step succeeds.

## Appearance

Not applicable — this is a window-state coordination and persistence
service, not a visual component.

## States

Not applicable — this is a window-state coordination and persistence
service, not a visual component.

## Accessibility

Not applicable — this is a window-state coordination and persistence
service, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wm-001 | terminating-default, terminating-latch | Fresh manager; post the app-termination notification | The termination flag is false before, true after (`WindowManagerTerminationTests`) |
| wm-002 | terminating-consumer | Visibility-persisting controller shown (visibility true); termination flag true; call the window-will-close callback | Persisted visibility stays true |
| wm-003 | terminating-consumer | Same, termination flag false; call the window-will-close callback | Persisted visibility becomes false |
| wm-004 | recent-limit-write | Recent-windows-count set to 7, apply the recent-document count from settings; then set to 3 and apply again | The platform's recent-documents limit setting reads 7, then 3 (`WindowManagerRecentsTests`) |
| wm-005 | recent-limit-mirror, recent-limit-on-init | Touch the shared window manager; set recent-windows-count to 12; wait one main-queue turn | The platform's recent-documents limit setting reads 12 |
| wm-006 | register-restorable, restore-builds-all | Register factories alpha and beta; run the launch-restore pass | Both factories ran; built set is {alpha, beta} (`WindowManagerSimulatedRelaunchTests`) |
| wm-007 | register-restorable | Register a restorable id without running the launch-restore pass | Factory has not run |
| wm-008 | register-restorable | Register two factories under the same id; run the launch-restore pass | Only the second factory runs |
| wm-009 | restore-visibility-pass, restore-visibility-rule | Registered visibility-persisting controller with persisted visibility true; run the launch-restore pass | Window is shown |
| wm-010 | restore-visibility-rule | Same with persisted false, and again with no persisted value | Window stays closed in both cases |
| wm-011 | restore-missing-factory-log | The platform-preferences storage backend holding visibility true for "ghost"; no factory, no controller; run the launch-restore pass | One error log naming "ghost" |
| wm-012 | reopen-no-app | A process with no running app instance; run the reopen-recents step | Returns; no crash; nothing opened |
| wm-013 | reopen-policy | The reopen decision for "match the system setting"/"always"/"never" with the system default true and false | true/false; true/true; false/false |
| wm-014 | reopen-disabled-closes, reopen-disabled-keeps-others | Reopen-on-launch policy "never"; one document window and one non-document window open; run the reopen-recents step | Document window's controller closed; non-document window still open |
| wm-015 | reopen-enabled-opens-recents | Reopen-on-launch policy "always"; recents [A, B]; A already open | One open request, for B, with display requested |
| wm-016 | close-ignored | Record an interaction with kind "close" for a document controller whose spec includes "include in recents" | No recent URL noted |
| wm-017 | spec-gate | A "show" interaction for a document controller whose spec does not include "include in recents" (and one with no spec) | No recent URL noted |
| wm-018 | document-recent | A "show" interaction for a controller with default behavior and document URL U | The platform's recent-documents API is passed U once |
| wm-019 | registry-register, registry-lookup | Register controller a; look up a and b | Returns the controller for a, nothing for b |
| wm-020 | registry-empty-id | Register a controller with an empty window id | The registered-ids list is empty |
| wm-021 | registry-registered-ids, registry-has-visible | Register a controller without showing it | The registered-ids list contains it; the has-visible-window flag is false (`WindowRegistryVisibilityTests`) |
| wm-022 | registry-visible-ids, registry-has-visible | Register and show a controller | The visible-ids list contains it; the has-visible-window flag is true |
| wm-023 | registry-has-visible | Show then dismiss the only controller | The has-visible-window flag is false |
| wm-024 | registry-has-visible | One closed and one shown controller | The has-visible-window flag is true |
| wm-025 | registry-lookup, registry-no-pruning | Register, show, dismiss, release the only strong reference | Looking the controller up returns nothing; the has-visible-window flag is false |
| wm-026 | storage-visibility-tristate | Fresh key; load; save false; load | Nothing, then false |
| wm-027 | storage-remove | Save state and visibility for w; remove both; load both | Both return nothing |
| wm-028 | storage-key-format, namespace-default | Namespace empty; save visibility for "log" with default prefixes | Underlying key is `WindowVisible_log` |
| wm-029 | namespace-default, namespace-qualify | Qualify the key `WindowState_log` with no namespace set | `WindowState_log` (`WindowStateNamespaceTests`) |
| wm-030 | namespace-token, namespace-stable | Isolate to the path `/a/worktree/Stenographer.app` | Current prefix is `Instance2e03b243_`; same value on a repeat call |
| wm-031 | namespace-token | Isolate to the path `/another/worktree/Stenographer.app` | Current prefix is `Instance30aace28_`, differs from wm-030 |
| wm-032 | namespace-no-raw-path | Isolate to the path `/Users/someone/secret-project/Stenographer.app` | Current prefix contains neither "someone" nor "secret-project" |
| wm-033 | storage-namespace-late-binding, userdefaults-visible-ids | Save state and visibility true for "log" un-namespaced; isolate; load both and list visible ids; save visibility false; reset; load | Namespaced loads are nothing and "log" is not listed; after reset visibility is true and "log" is listed |
| wm-034 | namespace-reset | Isolate to any path, then reset the namespace | Current prefix is the empty string |
| wm-035 | storage-state-json | Save a state through the settings-store-backed storage backend over a platform-preferences-backed store; load through the platform-preferences storage backend | Equal state returned |
| wm-036 | settings-store-non-bool-visibility | Write the string "x" under `WindowVisible_w`; load via each implementation | The settings-store-backed backend returns false; the platform-preferences backend returns nothing |
| wm-037 | visible-ids-default | Storage that omits the visible-window-ids operation | Returns an empty list |
| wm-038 | screenshot-capture | The own-window-capture operation for window handle 0 | Nothing (`WindowScreenshotTests`) |
| wm-039 | screenshot-png-offscreen | The write-PNG operation on a never-ordered-in (off-screen) window | Returns false; no file at the URL |
| wm-040 | screenshot-png-success | The write-PNG operation on an on-screen window owned by the process, writable URL | Returns true; file holds PNG data |
| wm-041 | screenshot-png-failure | On-screen window; URL in a non-existent directory | Returns false |
| wm-042 | single-screen-manager | A window manager constructed with a screen provider and storage but no screen manager | Its frame manager uses the shared screen manager |

## Edge Cases

- **Empty window ID**: Registering a controller MUST ignore one with an
  empty window id; storage calls with an empty id compose a key that is
  just the prefix and MUST behave like any other key.
- **Duplicate registration**: Re-registering an id MUST replace the
  previous weak entry; the earlier controller is no longer reachable
  through the registry even if still alive.
- **Duplicate restorable ID**: A second registration for the same id MUST
  replace the first factory.
- **Factory that does not register**: A factory that builds nothing, or
  builds a controller that is not registered, MUST NOT stop the pass; if
  its window was persisted visible, the missing-factory check does not fire
  because a factory exists for the id (the check only looks for a missing
  factory and a missing controller together).
- **Repeated restore**: Running the launch-restore pass twice MUST rerun
  every factory; idempotence of the factories is the host's responsibility.
- **Ordering**: Factory execution and the registry visibility pass MUST run
  in dictionary order, which is unspecified; a host that needs one window
  shown before another cannot rely on registration order.
- **Headless run**: The reopen-recents step MUST return without effect
  when there is no running app instance (unit tests).
- **Recent URL already open**: A recent URL that matches an open document's
  file URL MUST NOT be opened again.
- **Recent document missing on disk**: The open request is issued; the
  failure is discarded (see the open question on reopen-open-failure).
- **Recents limit out of range**: A zero or negative recent-windows-count
  value MUST be written to the platform's recent-documents limit setting
  unchanged; how the platform interprets it is the platform's behavior.
- **Termination during close**: Windows closed by the platform after the
  app-termination notification MUST keep their persisted visibility; once
  latched, the termination flag never clears within the process.
- **Deallocated controller**: A registry entry whose controller was
  released MUST read as absent from lookup, the registered-ids list, the
  visible-ids list, and the has-visible-window flag.
- **Sunk window**: A window sunk behind the desktop by quiet presentation
  MUST still count as visible
  (`WindowRegistryVisibilityTests.testASunkWindowStillCountsAsVisible`).
- **Undecodable stored state**: Corrupt or non-JSON data under a
  `WindowState_` key MUST read as nothing; the next save overwrites it.
- **Missing or non-boolean visibility value**: A missing key MUST read as
  nothing in both implementations; a non-boolean value reads as nothing in
  the platform-preferences implementation and false in the
  settings-store-backed implementation.
- **Two app copies**: Without isolating to the running bundle, two builds
  sharing an app identity MUST share window-state keys; the last writer
  wins.
- **Namespace changed mid-run**: Keys written before a namespace change
  MUST stay under the old prefix and are not migrated.
- **Namespace collision**: Two paths whose SHA-256 digests share their
  first 4 bytes MUST share a namespace (a 1-in-2^32 chance per pair); the
  source accepts this.
- **Concurrent access**: All manager, registry, and storage operations run
  on the window manager's single designated thread and are serialized; the
  window-state namespace's reads and writes are serialized by its own
  lock.
- **Missing capture symbol**: If the platform stops exporting its
  window-list image capture facility, the own-window-capture operation MUST
  return nothing and the write-PNG operation MUST return false.
- **Unwritable screenshot URL**: The write error MUST be converted to a
  false return; the error itself is not surfaced.
- **Offline or disconnected state**: Not applicable; the component
  performs no network I/O.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Screen provider | The screen provider | The live screen provider | Source of live screens, passed to the frame manager. |
| Storage | The window-state storage protocol | The settings-store-backed storage backend, using the shared settings store | Persistence for frames and visibility. |
| Screen manager | The screen manager | none (resolved to the shared screen manager) | Owner of the screen-set list and screen-change observer. |
| State-key prefix | Text | `"WindowState_"` | Frame-state key prefix (both storage implementations). |
| Visibility-key prefix | Text | `"WindowVisible_"` | Visibility key prefix (both storage implementations). |
| Settings store | The settings store | none (required) | Store backing the settings-store-backed storage backend. |
| Recent-windows-count setting | An integer setting | 10 | Mirrored into the platform's recent-documents limit setting. |
| Reopen-on-launch-policy setting | A policy setting ("match the system setting" / "always" / "never") | "match the system setting" | Whether recent documents reopen at launch. |
| Platform reopen-windows-on-quit default | system default (boolean) | false when absent | System default consulted by "match the system setting". |
| Platform recent-documents limit | platform setting (integer) | written by the manager | The platform's recent-documents cap. |
| Window-state namespace | process-wide prefix | "" | Set by isolating to the running bundle or to a path, cleared by resetting. |
| Restorable factories | a map of id to factory callback | empty | Registered by the host via the restorable-registration operation. |

## Deep Linking

Not applicable: the component registers no URL scheme or route; restore is
driven by the launch-restore pass and document recents by the platform's
document controller.

## Localization

Not applicable: the component produces no user-facing strings; its only
text is a developer log line and the display name of the
reopen-on-launch-policy setting, which belongs to the settings UI rather
than this component.

## Accessibility Options

Not applicable: the component renders nothing, so Reduce Motion, Increase
Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no feature flag; the user settings it
reads (the recent-windows-count and reopen-on-launch-policy settings) are
preferences, not flags.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

- **Data collected**: Per window id, a persisted window state (frame
  placements per screen set, including display identifier and localized
  display name fingerprints) and a visibility boolean; document URLs
  passed to the platform's recent-documents list.
- **Storage**: Window state and visibility in the settings store's
  non-secure provider (the platform's local preferences store by default)
  or directly in that same local preferences store; recents in the
  platform's recent-documents store. The namespace prefix is a hash, so a
  build path never reaches the preferences file.
- **Transmission**: None from this component; a settings store backed by
  an iCloud-syncing provider syncs these keys through that provider.
- **Retention**: Until removed by the remove-state or remove-visibility
  operations, or the preferences domain is deleted; recents are capped by
  the platform's recent-documents limit setting.

## Logging

Subsystem: `com.agentic-cookbook.agentictoolkit` | Category: `WindowManager`

| Event | Level | Message |
|-------|-------|---------|
| Persisted-visible window with no factory and no live controller during the launch-restore pass | error | `restoreOnLaunch: visible window '<id>' has no registered factory` (ID public) |

Registry changes, storage reads and writes, codec failures, reopen
decisions, document-open failures and screenshot failures are not logged.

## Platform Notes

- **SwiftUI**: No SwiftUI in the source. A SwiftUI macOS app gets frame
  persistence from `Window`/`WindowGroup` scene autosave and
  `defaultPosition`/`defaultSize`, and document recents from
  `DocumentGroup`; launch restore of utility windows still needs a
  coordinator like this one calling `openWindow(id:)` for IDs saved
  visible, with `@AppStorage` or `SceneStorage` in place of
  `WindowStateStorage`.
- **Compose**: Compose for Android has no multi-window desktop model; a
  Compose Desktop port starts from `rememberWindowState` and
  `WindowPosition`, persists with DataStore plus `kotlinx.serialization`,
  keeps the registry as a `Map<String, WeakReference<…>>` confined to
  `Dispatchers.Main`, and replaces the termination latch with an
  `ApplicationScope` exit hook. The namespace hash maps to
  `MessageDigest.getInstance("SHA-256")`.
- **React/Web**: Browsers own window placement; an Electron port starts
  from `BrowserWindow.getBounds`/`setBounds`, `app.on('before-quit')` for
  the termination latch, `app.addRecentDocument` for recents,
  `electron-store` or `localStorage` with `JSON.stringify` for storage,
  `webContents.capturePage()` for screenshots, and Node
  `crypto.createHash('sha256')` for the namespace.
- **AppKit / UIKit**: Source files: `WindowManager.swift` (Combine sink on
  `UserSettings.recentWindowsCount`, mirrored into the `NSRecentDocumentsLimit`
  user default; `NSQuitAlwaysKeepsWindows` read for the system reopen
  default; selector-based `NotificationCenter` observer for
  `willTerminateNotification`, `os.Logger`, `NSDocumentController` recents
  and reopen), `WindowRegistry.swift` (weak boxes over
  `SingleWindowController`), `WindowStateStorage.swift`,
  `SettingsStoreWindowStateStorage.swift` (`StorableSetting` keys through
  `SettingsStore`), `UserDefaultsWindowStateStorage.swift`
  (`JSONEncoder`/`JSONDecoder` over `UserDefaults.standard`,
  `dictionaryRepresentation()` scan), `WindowStateNamespace.swift`
  (`OSAllocatedUnfairLock`, CryptoKit `SHA256`), `WindowScreenshot.swift`
  (`dlsym` of `CGWindowListCreateImage`, `NSBitmapImageRep` PNG). UIKit has
  no free-floating windows; scene restoration
  (`stateRestorationActivity`, `UISceneSession.userInfo`) replaces frame
  and visibility persistence.
- **WinUI 3**: Start from `Microsoft.UI.Windowing.AppWindow` (`Position`,
  `Size`, `MoveAndResize`, `Show`/`Hide`, `IsVisible`, `Closing` event) with
  `DisplayArea` for screen bounds. Keep the manager and registry on the UI
  thread via `DispatcherQueue`; hold controllers in a
  `Dictionary<string, WeakReference<T>>` and expose `VisibleIds`/
  `HasVisibleWindow` through `INotifyPropertyChanged` if bound. Persist
  `PersistedWindowState` with `System.Text.Json` into
  `Windows.Storage.ApplicationData.Current.LocalSettings` (the 8 KB
  per-value limit favors one key per window, as the source already does)
  and store visibility as a native `bool` value so absence stays
  distinguishable via `ContainsKey`. Replace `willTerminateNotification`
  with `Application.Current` exit handling or `AppWindow.Closing` plus an
  app-level shutdown flag; replace the Combine settings sink with a
  `PropertyChanged` handler. Document recents map to
  `Windows.Storage.AccessCache.StorageApplicationPermissions.MostRecentlyUsedList`
  (with `MaximumItemsAllowed` in place of `NSRecentDocumentsLimit`) and
  jump lists (`Windows.UI.StartScreen.JumpList`). The namespace hash is
  `System.Security.Cryptography.SHA256.HashData`, guarded with `lock`.
  Own-window screenshots use `Windows.Graphics.Capture` with
  `GraphicsCaptureItem.TryCreateFromWindowId` or `RenderTargetBitmap` for
  XAML content, encoded with `BitmapEncoder.PngEncoderId`. Windows
  coordinates are top-left origin, unlike AppKit.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/SettingsStoreWindowStateStorage.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/UserDefaultsWindowStateStorage.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/WindowManager.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/WindowRegistry.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/WindowScreenshot.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/WindowStateNamespace.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/WindowStateStorage.swift` |

## Design Decisions

**Decision**: `WindowManager` is a thin coordinator over two sub-services (`frames`, `registry`) instead of one type that does everything.
**Rationale**: The type doc comment directs most callers to a sub-service (`frames.restoreFrame(...)`, `registry.controller(forID:)`); frame persistence and live lookup change independently.
**Approved**: pending

**Decision**: An omitted `screenManager` resolves to `ScreenManager.shared`, never a new instance.
**Rationale**: Per the initializer comment, a second `ScreenManager` on the same persistence key would clobber the real one's state and double-register the notification observer.
**Approved**: pending

**Decision**: Termination is latched with a one-way `isTerminating` flag read by `SingleWindowController.windowWillClose(_:)`.
**Rationale**: AppKit sends `windowWillClose:` to still-visible windows after `applicationWillTerminate`; persisting hidden there stopped windows left open from reopening (`WindowManagerTerminationTests`).
**Approved**: pending

**Decision**: Restore is driven by registered factories (`registerRestorable`) rather than hosts hand-constructing controllers.
**Rationale**: The doc comment says this ensures "a window can't silently miss restore"; the missing-factory error log exists to surface the remaining wiring gap loudly.
**Approved**: pending

**Decision**: The recent-documents cap is set by writing the `NSRecentDocumentsLimit` user default.
**Rationale**: `NSDocumentController.maximumRecentDocumentCount` is read-only; the default is the public knob and avoids subclassing `NSDocumentController`.
**Approved**: pending

**Decision**: When reopen is disabled the manager actively closes document windows AppKit restored.
**Rationale**: The comment calls this overriding AppKit's own state restoration; it closes through the window controller so the controller, not just the window, is torn down.
**Approved**: pending

**Decision**: The registry holds weak references and never prunes dead entries.
**Rationale**: A dropped controller "naturally disappears" from lookups; the number of window IDs is small and bounded, so dead boxes cost little.
**Approved**: pending

**Decision**: `WindowStateNamespace` is a process-wide lock-guarded static read at key-composition time, not an injected dependency.
**Rationale**: `WindowManager.shared` builds its storage on first access from anywhere, so an injected namespace would miss the storages that matter; the lock (not `@MainActor`) lets non-main-actor code compose the same keys.
**Approved**: pending

**Decision**: The namespace is an 8-hex-character SHA-256 prefix of the bundle path, empty by default.
**Rationale**: The bundle path is the identity that differs between two copies (bundle ID is shared, pid changes each launch); hashing keeps keys short and keeps directory names out of preferences; the empty default preserves every existing installation's layout.
**Approved**: pending

**Decision**: Both storage implementations use the same key formats and encodings (JSON state, native boolean visibility).
**Rationale**: Swapping `SettingsStoreWindowStateStorage` in over a UserDefaults-backed store reads existing state without migration, per its doc comment.
**Approved**: pending

**Decision**: `WindowScreenshot` resolves the deprecated `CGWindowListCreateImage` through `dlsym`.
**Rationale**: ScreenCaptureKit is async and requires Screen Recording permission even for own windows; the legacy symbol works without permission, and runtime resolution avoids the deprecation warning while degrading to `nil` if the symbol disappears.
**Approved**: pending

**Decision**: Non-document single windows are not recorded in recents yet.
**Rationale**: The source marks this intentional, pending `WindowRecentsTracker` in a follow-up slice.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | Best Practices |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | partial | Reliability |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |

separation-of-concerns passes because frame persistence (`WindowFrameManager`), live lookup (`WindowRegistry`), storage (`WindowStateStorage` and its two implementations), key namespacing (`WindowStateNamespace`) and capture (`WindowScreenshot`) are separate types behind a thin coordinator. unit-test-coverage is partial: the termination latch, recent-limit mirror, factory execution, registry visibility, namespace isolation and screenshot failure paths have tests, but `reopenRecentsOnLaunch()`, `windowDidInteract(_:kind:)` and the missing-factory log do not. explicit-error-handling fails because storage encode/decode failures and document-open failures are discarded without a signal (the open questions on storage-codec-failure and reopen-open-failure). data-integrity is partial because corrupt stored state reads as never-saved and is overwritten, and the two storage implementations disagree on a non-boolean visibility value. state-recovery passes because frames and visibility persist across launches and `restoreOnLaunch()` replays them. graceful-degradation passes because a headless run skips reopen, a missing capture symbol yields `nil`, and an empty window ID is ignored. health-observability is partial because the missing-factory wiring gap is logged, but that check is inert under the default storage (the open question on visible-ids-settings-store). main-thread-freedom passes because every main-actor operation is bounded by the number of window IDs or recent documents, and document opening is asynchronous. no-pii-in-logs passes because the single log line carries only a host-chosen window ID. data-minimization passes because the namespace stores a hash instead of the bundle path.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/windows/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `WindowManager.swift`, `WindowRegistry.swift`, `WindowStateStorage.swift`, `SettingsStoreWindowStateStorage.swift`, `UserDefaultsWindowStateStorage.swift`, `WindowStateNamespace.swift`, `WindowScreenshot.swift` and their tests |
