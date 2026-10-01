---
id: 016f5ba0-f4ee-4b39-b1a2-83629768acdd
title: File System
domain: agentictoolkit://cookbook/foundation/file-system
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Seven asynchronous file-system operations served from one serial queue,
  a typed file-system error outcome, and a file signature's size-and-date change
  check.
platforms:
- swift
- macos
tags:
- filesystem
- concurrency
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/host/extension-host
- agentictoolkit://cookbook/workspace/extensions/vscode-api/workspace/main-thread-workspace
references:
- packages/apple/AgenticToolkit/Core/FileSystem/FileSystemService.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/FileSystem/FileSystemServicing.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/FileSystem/FileSignature.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/FileSystem/FileSystemServiceTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/FileSystem/FileSignatureTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

## Overview

The file system service is the one place in the toolkit that touches the
real file system on the caller's behalf. It wraps the platform's
file-system APIs behind seven asynchronous operations — read file, read
directory, stat, write file, create directory, delete, and rename — each
running its blocking file-system work on one private serial background
queue and bridging back to the caller's asynchronous call. It knows nothing
about URIs, workspaces, or extensions; a caller holding a URL converts to a
path string before calling in, and the workspace layer that implements VS
Code's `vscode.workspace.fs` surface is documented as the sole caller today.

Alongside it, the file signature is an unrelated but co-located value: a
cheap size-and-modification-date pair used to answer "has this file
changed?" without reading its bytes. A matching substitution interface
exists solely so a test double can stand in for the service.

Every operation classifies its own failures into one file-system error
outcome — trying a lower-level operating-system error code first, then a
higher-level framework error code — so a caller gets a not-found,
already-exists, is-a-directory, not-a-directory, directory-not-empty, or
no-permissions outcome where the source can tell, and an operation-shaped
fallback (read-failed, write-failed, stat-failed, read-directory-failed,
delete-failed, rename-failed, create-directory-failed) carrying the
original error otherwise.

## Behavioral Requirements

- **file-signature-shape**: The file signature MUST be an immutable,
  comparable value with exactly two stored properties, `size` (an integer
  byte count) and `modified` (a date/time), constructible directly from
  those two values.
- **file-signature-stat-source**: Deriving a file signature MUST read
  `size` and `modified` from a fresh, path-based attribute lookup, never
  from a URL's cached resource-value lookup, because a URL caches resource
  values it has already been asked for and a second signature taken from
  the same URL value would repeat the first one's numbers regardless of
  what changed on disk.
- **file-signature-absence-is-nil**: Deriving a file signature MUST answer
  nothing (no signature), not throw, when nothing can be stat'd at the
  given location — no such file, no permission, or a path that does not
  resolve to a file — leaving the caller to decide what absence means.
- **file-signature-equality-limit**: File signature equality MUST compare
  only `size` and `modified`; a rewrite that lands on the same byte count
  and the same modification date is indistinguishable from no change at
  all, and this is documented as the type's known limit rather than
  treated as a defect.
- **error-type-shape**: The file-system error outcome MUST be an error type
  carrying a localized description, and MUST NOT be required to support
  equality comparison or safe cross-thread sharing, because at least one
  outcome (no-permissions) carries an underlying cause a caller may need to
  branch on directly rather than through its description text.
- **error-cases-name-a-path**: Every file-system error outcome MUST carry
  the path (and, for the rename-failed outcome, also the destination path)
  that the failing operation was called with, so a caught error names the
  location it applies to.
- **error-description-fixed-strings**: The file-system error outcome's
  description text MUST return one hardcoded English sentence per outcome,
  built by string interpolation, with no localization lookup of any kind.
- **concurrent-call-safety**: The file system service MUST be safe to call
  concurrently from any thread or concurrent task with no additional
  synchronization at the call site.
- **serial-queue-backing**: The file system service MUST run every one of
  its seven operations' blocking file-system work on one private, serial
  background queue, created once at construction and never replaced.
- **continuation-bridge**: The service's internal call-bridging step MUST
  bridge the queue's synchronous, throwing work back into the caller's
  asynchronous call, so the calling task suspends rather than blocking a
  cooperative-pool thread while the work runs on the queue.
- **calls-serialize-on-the-queue**: Two or more calls into the same file
  system service instance MUST be served in the order their work is
  enqueued onto that instance's single background queue, never interleaved
  with each other at a sub-call granularity.
- **fresh-file-manager-per-call**: Every operation MUST use its own
  underlying file-manager instance for its queued work rather than sharing
  one across calls, because the underlying file-manager type is not safe to
  share across the boundary between the calling context and the background
  queue.
- **independent-instances**: Constructing the file system service MUST take
  no parameters and own no state beyond its own queue, so multiple
  instances may coexist, each with its own independent serial queue and no
  ordering guarantee between them.
- **read-file-follows-links**: The read-file operation MUST follow a
  symbolic link at the given path to its target's bytes, as reading a file
  always does.
- **read-file-not-found**: The read-file operation MUST throw a not-found
  outcome when nothing resolves at the given path, including a dangling
  symbolic link.
- **read-file-is-a-directory**: The read-file operation MUST throw an
  is-a-directory outcome when the given path resolves to a directory.
- **read-file-exact-bytes**: The read-file operation MUST answer exactly
  the bytes on disk at the given path, with no transformation.
- **read-directory-entry-shape**: The read-directory operation MUST answer
  one entry per child of the given path, where each entry carries the
  child's own last path component as its name and a type bitmask; the
  listing MUST NOT be recursive.
- **read-directory-follows-link**: The read-directory operation MUST follow
  a symbolic link at the given path and list the directory it points to
  before enumerating children.
- **read-directory-not-a-directory**: The read-directory operation MUST
  throw a not-a-directory outcome when the given path does not resolve to a
  directory.
- **read-directory-unreadable-child-is-unknown**: The read-directory
  operation MUST report a child whose own type cannot be determined with an
  unknown-type flag rather than aborting or throwing for that one child,
  while a failure to read the given path itself still throws.
- **read-directory-link-child-union-bits**: A child that is a symbolic link
  MUST be reported with the union of the symbolic-link flag and its
  resolved target's type bit where the target's type can be determined —
  raw value 65 for a link to a file, 66 for a link to a directory, the
  symbolic-link flag alone when the target is gone — never the
  symbolic-link flag alone for a resolvable target.
- **stat-does-not-follow-terminal-link**: The stat operation MUST NOT
  follow a terminal symbolic link at the given path; it MUST report the
  link's own type, timestamps, and size, not its target's.
- **stat-link-target-bit-union**: The stat operation MUST set the
  symbolic-link flag together with the resolved target's own type bit where
  that can be determined cheaply — raw value 65 for a link to a file, 66
  for a link to a directory — and the symbolic-link flag alone when the
  target does not exist.
- **stat-optional-timestamps**: A stat result's creation date and
  modification date MUST each be absent when the underlying lookup does not
  report that attribute, never coerced to a placeholder date.
- **stat-size-fallback**: A stat result's size MUST fall back to `0` when
  the underlying lookup does not report a size attribute.
- **stat-missing-path**: The stat operation MUST throw a not-found outcome
  when nothing is at the given path.
- **write-file-create-flag**: The write-file operation MUST throw a
  not-found outcome, writing nothing, when nothing exists at the given path
  and the create flag is false; it MUST write and create the path when the
  create flag is true.
- **write-file-overwrite-flag**: The write-file operation MUST throw an
  already-exists outcome, leaving the existing bytes untouched, when
  something already exists at the given path and the overwrite flag is
  false; it MUST replace the bytes when the overwrite flag is true.
- **write-file-onto-directory**: The write-file operation MUST throw an
  is-a-directory outcome when the given path resolves to a directory,
  regardless of the flags.
- **write-file-existence-at-the-link**: The write-file operation's
  existence check MUST be judged at the link, not through it, so a dangling
  symbolic link at the given path counts as something already there for the
  overwrite check.
- **write-file-not-atomic**: The write-file operation MUST write its
  contents in place, never via a temporary file renamed over the
  destination, so an existing file's identity and permissions are preserved
  and a write through a symbolic link lands on the link's target rather
  than replacing the link itself.
- **create-directory-with-parents**: The create-directory operation MUST
  create the given path and every missing intermediate parent directory in
  one call.
- **create-directory-idempotent**: The create-directory operation MUST
  succeed with no error when the given path already resolves to a
  directory.
- **create-directory-exists-error**: The create-directory operation MUST
  throw an already-exists outcome when something that is not a directory
  already exists at the given path.
- **delete-link-not-target**: The delete operation MUST delete a symbolic
  link at the given path as the link itself, leaving its target untouched.
- **delete-not-found**: The delete operation MUST throw a not-found outcome
  when nothing is at the given path.
- **delete-nonrecursive-emptiness-check**: The delete operation, with the
  recursive flag false, MUST throw a directory-not-empty outcome and delete
  nothing when the given path is a directory with any entries in it; it
  MUST succeed when the directory has none.
- **delete-recursive-flag-scope**: The recursive flag's only effect MUST be
  the emptiness check above — the underlying removal itself recurses
  unconditionally regardless of the flag, so the recursive flag set true
  against a populated directory MUST remove it and its contents in one
  call.
- **delete-trash-flag**: The delete operation, with the Trash option set,
  MUST move the item to the user's Trash instead of permanently removing
  it; with the Trash option unset, it MUST permanently remove the item.
- **delete-trash-location-not-surfaced**: The delete operation MUST NOT
  report where a trashed item landed, because the Trash may rename an item
  to avoid a collision and no member of this component answers that
  renamed location.
- **rename-is-one-move**: The rename operation MUST treat rename and move
  as the same single operation, backed by one move call on the
  non-conflicting path.
- **rename-source-not-found**: The rename operation MUST throw a not-found
  outcome naming the source path, leaving the destination path untouched,
  when nothing is at the source path.
- **rename-destination-not-precchecked**: The rename operation MUST NOT
  pre-check whether the destination path is occupied before attempting the
  move; it MUST attempt the move first and act on the overwrite flag only
  after that move fails in a way classified as an already-exists outcome.
- **rename-case-only-and-self-renames-succeed**: A rename that only changes
  the case of a name on a case-insensitive volume, and a rename where the
  source and destination path are identical, MUST succeed regardless of the
  overwrite flag, because the underlying move succeeds outright and the
  overwrite flag is never consulted on that path.
- **rename-overwrite-refusal**: The rename operation, with the overwrite
  flag false, MUST throw an already-exists outcome naming the destination
  path and move nothing when the move fails because a distinct item already
  occupies the destination path.
- **rename-overwrite-guards**: The rename operation, with the overwrite
  flag true, before removing an occupied destination path, MUST reproduce
  the underlying move operation's own three refusals: an is-a-directory
  outcome for a non-directory source onto a directory destination, a
  not-a-directory outcome for the reverse, and a directory-not-empty
  outcome for a directory destination that has entries in it.
- **rename-overwrite-sequence**: The rename operation, with the overwrite
  flag true, onto a genuinely occupied destination, MUST proceed as move,
  remove, move again — attempt the move, remove the occupying item once the
  guards above clear it, then retry the move — never a single atomic
  replace, because no available operation atomically replaces a
  destination spanning files and directories alike.
- **rename-overwrite-failure-window**: If the removal step of the
  overwrite sequence succeeds but the retried move then fails, the
  destination path's former contents MUST be gone with nothing put back,
  the source path MUST still be in place, and the caller MUST receive a
  rename-failed outcome naming both paths — this window is a documented,
  accepted risk of the sequence, not a defect this component attempts to
  close.
- **rename-hard-link-and-inode-identity**: The rename operation MUST rely
  on the underlying move and remove operations to distinguish a hard link
  from a case-only alias, rather than comparing paths, folded case, or
  low-level file identity itself, because either of those comparisons is
  indistinguishable from a legitimate rename the caller is entitled to
  make.
- **servicing-interface-mirrors-service**: The substitution interface MUST
  declare exactly the seven operations the file system service exposes,
  with identical signatures, and MUST itself be safe to share across
  concurrent callers.
- **servicing-conformance-is-free**: The file system service MUST satisfy
  the substitution interface with no additional code, because every
  operation the interface requires is already implemented with a matching
  signature.
- **error-classification-posix-first**: Classifying a thrown error into a
  file-system error outcome MUST check the error's low-level
  operating-system error code before consulting its higher-level framework
  error code, because the two independently-observed routes to a move
  failure surface the low-level code first.
- **error-classification-chain-depth-bound**: Searching a thrown error's
  chain of nested underlying errors for a low-level operating-system error
  code MUST stop after 4 levels, as a guard against a cyclic chain rather
  than a claim about how deep that chain nests errors.
- **error-classification-fallback**: When classification recognizes
  nothing in a thrown error, every operation MUST fall back to its own
  operation-shaped error outcome carrying the original error.
- **permission-detection-best-effort**: Detecting a no-permissions outcome
  MUST be best-effort — it fires only when a higher-level framework error
  names a permission-specific code or a permission-denied/operation-not-
  permitted code is reachable in the error's chain; a permission failure
  surfaced any other way MUST arrive as the calling operation's own
  operation-shaped fallback outcome instead.
- **concurrent-instance-ordering**: No lock, isolation mechanism, or
  ordering rule spans two independently-constructed file system service
  instances, or an external process, operating against the same path
  concurrently; each instance's own serial queue orders only its own calls,
  so the write-file operation's existence check and write, the
  create-directory operation's existence check and create, and the delete
  operation's emptiness check and removal are each atomic only relative to
  that one instance's queue, never relative to a second instance or process
  racing the same path in between.

## Appearance

Not applicable — this is a file-system service, not a visual component.

## States

Not applicable — this is a file-system service, not a visual component.

## Accessibility

Not applicable — this is a file-system service, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| file-system-001 | file-signature-shape, file-signature-stat-source | Read the file signature twice in a row against an untouched 8-byte file. | Both signatures are equal; the first one's size is 8. |
| file-system-002 | file-signature-equality-limit | Read the file signature before and after a rewrite that changes both length and modification date. | The two signatures are unequal. |
| file-system-003 | file-signature-equality-limit | Read the file signature before and after a rewrite pinned to the same modification date as the original. | The two signatures are equal, by design. |
| file-system-004 | file-signature-absence-is-nil | Read the file signature for a location naming nothing on disk. | Returns nothing (no signature), without throwing. |
| file-system-005 | read-file-exact-bytes | Perform the read-file operation against a file whose bytes are known. | Returns exactly those bytes. |
| file-system-006 | read-file-not-found | Perform the read-file operation against a path with nothing there. | Throws a not-found outcome. |
| file-system-007 | read-file-is-a-directory | Perform the read-file operation against a directory path. | Throws an is-a-directory outcome. |
| file-system-008 | read-directory-entry-shape, read-directory-link-child-union-bits | Perform the read-directory operation against a directory holding a plain file, a subdirectory, and a symbolic link to the file. | Answers one entry per child; the link entry's type bitmask equals 65. |
| file-system-009 | read-directory-follows-link | Perform the read-directory operation against a path that is itself a symbolic link to a directory. | Lists the target directory's children. |
| file-system-010 | read-directory-not-a-directory | Perform the read-directory operation against a plain file's path. | Throws a not-a-directory outcome. |
| file-system-011 | stat-does-not-follow-terminal-link, stat-link-target-bit-union | Perform the stat operation against a symbolic link to a file, a symbolic link to a directory, and a dangling symbolic link. | Type bitmask values 65, 66, and 64 respectively. |
| file-system-012 | stat-does-not-follow-terminal-link | Perform the stat operation against a symbolic link whose own path string is shorter than its target's contents. | The reported size equals the link's own path-string byte length, not the target's size. |
| file-system-013 | stat-missing-path | Perform the stat operation against a path with nothing there. | Throws a not-found outcome. |
| file-system-014 | write-file-create-flag | Perform the write-file operation with the create flag false against a missing path. | Throws a not-found outcome, writes nothing. |
| file-system-015 | write-file-create-flag | Perform the write-file operation with the create flag true against a missing path. | Succeeds; the path now holds the given contents. |
| file-system-016 | write-file-overwrite-flag | Perform the write-file operation with the overwrite flag false against an existing file. | Throws an already-exists outcome, leaves the original bytes. |
| file-system-017 | write-file-overwrite-flag | Perform the write-file operation with the overwrite flag true against an existing file. | Succeeds; the path now holds the new contents. |
| file-system-018 | write-file-onto-directory | Perform the write-file operation against a directory path. | Throws an is-a-directory outcome. |
| file-system-019 | create-directory-with-parents | Perform the create-directory operation against a path several missing intermediate levels deep. | Succeeds; the path and every missing parent now exist. |
| file-system-020 | create-directory-exists-error | Perform the create-directory operation against a path already occupied by a plain file. | Throws an already-exists outcome. |
| file-system-021 | delete-nonrecursive-emptiness-check | Perform the delete operation with the recursive flag false against a directory holding one entry, then against an emptied copy of the same directory. | The populated case throws a directory-not-empty outcome; the empty case succeeds. |
| file-system-022 | delete-recursive-flag-scope | Perform the delete operation with the recursive flag true against a directory holding several entries. | Succeeds; the directory and every entry in it are gone. |
| file-system-023 | delete-trash-flag | Perform the delete operation with the Trash option set against an ordinary file. | The file is no longer at the path; it is reachable through the user's Trash rather than permanently removed. |
| file-system-024 | delete-link-not-target | Perform the delete operation against a symbolic link to a file that still needs to exist afterward. | The link is gone; the file it pointed to still exists with its original contents. |
| file-system-025 | rename-case-only-and-self-renames-succeed | Perform the rename operation, changing only the case of a name on a case-insensitive volume, with the overwrite flag false. | Succeeds; the file still exists under the new casing. |
| file-system-026 | rename-case-only-and-self-renames-succeed | Perform the rename operation from a path onto itself, with the overwrite flag false. | Succeeds; the file is unchanged. |
| file-system-027 | rename-overwrite-refusal | Perform the rename operation with the overwrite flag false, where the destination already names a distinct file. | Throws an already-exists outcome, moves nothing. |
| file-system-028 | rename-overwrite-sequence | Perform the rename operation with the overwrite flag true, where the destination already names a distinct file. | Succeeds; the destination now holds the source's former contents, and the source no longer exists. |
| file-system-029 | rename-hard-link-and-inode-identity | Perform the rename operation with the overwrite flag true, where the destination is a hard link to a different name for the very inode already at the source's eventual destination shape. | The other name is replaced correctly rather than treated as identical to the source. |
| file-system-030 | calls-serialize-on-the-queue | Perform eight concurrent read-file operations into one service instance, each against a different file with distinct contents. | Each caller's call returns exactly its own file's bytes, with none mixed up. |

## Edge Cases

- **Null and empty input**: The read-file, read-directory, stat, delete,
  and both sides of the rename operation all treat an empty path string the
  same way they treat any other path nothing resolves at: the underlying
  file-system lookup reports it as absent, and the operation throws its
  not-found/not-a-directory-shaped outcome rather than a distinct "empty
  path" error, since no outcome singles that condition out. The write-file
  operation with zero-length contents MUST still create or replace the
  file — an empty file is a valid outcome, not an error — since writing
  bytes places no minimum-length requirement on its argument.
- **Boundary values**: The read-directory operation against a directory
  with zero children MUST answer an empty list, not throw, since listing a
  directory's contents succeeds on an empty directory the same way it does
  on a populated one. A path that is a symbolic-link chain terminating in
  another symbolic link (rather than a file or directory) is not addressed
  by any operation's own documentation; stat still reports the first link's
  own type without walking further, per **stat-does-not-follow-terminal-
  link**, while the read-file/read-directory link-following requirements
  resolve the whole chain because that is what the underlying path-based
  read operations do.
- **Concurrent access**: Per **concurrent-instance-ordering**, two service
  instances, or this component and an external process, racing the same
  path have no ordering, mutual exclusion, or overlap detection between
  them; each instance's serial queue only orders its own calls
  (**calls-serialize-on-the-queue** establishes that narrower guarantee,
  and no requirement here claims more).
- **Error states**: The rename operation's overwrite path
  (**rename-overwrite-sequence**) has a genuine, documented failure window
  — **rename-overwrite-failure-window** — where a successful removal of
  the occupying item followed by a failed retry move permanently loses that
  item's former contents; this component states this plainly rather than
  claiming a rollback it does not perform. Every other operation's failure
  modes are either a clean refusal before anything is written (a not-found
  outcome before a write, an already-exists/directory-not-empty outcome
  before a remove) or a best-effort classification
  (**permission-detection-best-effort**) that falls back to an
  operation-shaped error rather than misreporting the cause.
- **Offline / disconnected state**: Not applicable — every operation acts
  on a local file-system path; none of the three source units reference a
  network call or any remote dependency whose availability could vary.
- **Crash / power-loss recovery**: Not addressed by this component at all
  — the write-file operation writes in place (**write-file-not-atomic**)
  with no journal, temp file, or write barrier of its own, and the rename
  operation's overwrite sequence performs its remove-then-move-again steps
  with no on-disk marker that would let a later call detect and finish an
  interruption between them the way a recovery sweep would. A power loss
  between the removal and the retried move in
  **rename-overwrite-sequence** leaves exactly the state
  **rename-overwrite-failure-window** already documents as a live risk of
  an ordinary in-process failure at that same point — this component treats
  that window as accepted, not recoverable.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| path (read-file, read-directory, stat, create-directory) | string | none (required) | The file-system location the operation acts on; not a URL, so a caller converts before calling in. |
| source path, destination path (rename) | string | none (required) | The source and destination paths for the one move-backed rename. |
| path (delete) | string | none (required) | The file-system location to remove or move to the Trash. |
| contents (write-file) | bytes | none (required) | The exact bytes written to the path; never appended to or chunked. |
| create flag (write-file) | boolean | none (required) | When true, a missing path is created; when false, a missing path throws a not-found outcome. |
| overwrite flag (write-file) | boolean | none (required) | When true, an existing path is replaced; when false, an existing path throws an already-exists outcome. Independent of the create flag. |
| recursive flag (delete) | boolean | none (required) | When false, a non-empty directory throws a directory-not-empty outcome; the removal itself always recurses once it proceeds. |
| Trash option (delete) | boolean | none (required) | True routes through the user's Trash; false permanently removes the item. |
| overwrite flag (rename) | boolean | none (required) | Governs only what happens when the initial move fails because something distinct already occupies the destination path. |

The service's construction itself takes no parameters and exposes no
configurable state: each instance owns one private serial queue, fixed for
the instance's lifetime, and nothing about that queue's label, priority, or
behavior is caller-adjustable.

## Deep Linking

Not applicable: this component operates on file-system paths, not
application URLs or navigation destinations, and defines no deep-link
surface of its own.

## Localization

Not applicable in the sense of user-facing display strings needing
translation infrastructure, but not ideal either: the file-system error
outcome's description text builds every one of its case messages as a
hardcoded English sentence via string interpolation, with no localization
lookup anywhere in the source (**error-description-fixed-strings**). A
caller that surfaces that description directly in UI would show English
text regardless of the user's locale; the workspace layer that is the one
documented caller is itself recorded elsewhere as failing its own
no-hardcoded-strings check for passing these same strings through verbatim.

## Accessibility Options

Not applicable: this is a non-visual file-system service with no rendered
UI to respond to a reduced-motion, increased-contrast, or
color-differentiation accessibility setting.

## Feature Flags

Not applicable: this component declares no feature-flag or remote-config
lookup of any kind — every one of the seven operations and the file
signature's check runs the same fixed logic unconditionally.

## Analytics

Not applicable: this component contains no event-emission or telemetry
call of any kind — an operation either returns its result or throws its
file-system error outcome, with no recorded event either way.

## Privacy

- **Data collected**: This component collects nothing beyond the path
  strings and byte contents a caller already supplies as arguments; it
  reads no attribute beyond what each operation's own contract needs (type,
  timestamps, and size for stat; a directory listing's names and types for
  read-directory). The file signature reads only a file's size and
  modification date, never its contents.
- **Storage**: Every write, rename, and directory creation lands as
  ordinary, unencrypted files or directories at whatever path the caller
  names — this component applies no encryption, sandboxing, or
  access-control policy of its own, and relies entirely on the OS and the
  calling application's own sandbox entitlements for what paths are
  actually reachable.
- **Transmission**: Not applicable — nothing in this component makes a
  network call of any kind; every operation is local-disk-only.
- **Retention**: This component sets no retention or expiry policy of its
  own; a written or renamed item persists until a caller deletes it, and a
  delete call with the Trash option set moves an item to the user's Trash
  rather than erasing it immediately, extending its retention under the
  OS's own Trash lifecycle rather than this component's.
- **Path strings may be sensitive**: Every file-system error outcome
  interpolates the caller-supplied path verbatim into its description text
  (**error-description-fixed-strings**); on a typical desktop install that
  path routinely contains the user's account name (for example, under a
  per-user home directory), so a caller that logs or displays a caught
  error's description unfiltered is exposing that path segment wherever the
  error surfaces.

## Logging

This component performs no logging of its own — no logging call or
diagnostic breadcrumb of any kind appears anywhere in its source. Every
failure surfaces as a thrown, typed file-system error outcome instead of a
log line; a caller that wants a trail of what this component did must log
at its own call site.

## Platform Notes

- **SwiftUI**: Source: `packages/apple/AgenticToolkit/Core/FileSystem/
  FileSystemService.swift`, `Core/FileSystem/FileSystemServicing.swift`, and
  `Core/FileSystem/FileSignature.swift`. The type is plain `Foundation` with
  no SwiftUI dependency; a SwiftUI-hosted caller awaits one of the seven
  `async throws` operations from a `Task` and renders the returned value or
  caught `FileSystemServiceError` into its own `@State`/`@Observable` view
  state — `FileSystemService` itself holds none, and `AgenticToolkitCore`,
  the framework target that builds it, is configured `platform: macOS` in
  `packages/apple/AgenticToolkit/project.yml` today.
- **Compose**: On Kotlin/Android, port to a class exposing seven `suspend
  fun` equivalents (`readFile`, `readDirectory`, `stat`, `writeFile`,
  `createDirectory`, `delete`, `rename`), each running its `java.io.File`/
  `java.nio.file` work inside `withContext(Dispatchers.IO)` rather than the
  default coroutine dispatcher — Android's IO dispatcher is the analogue of
  this component's dedicated serial `DispatchQueue`, though it is a shared
  thread pool rather than one queue per instance, so a port that wants
  `calls-serialize-on-the-queue`'s ordering guarantee for one logical
  instance needs its own `Mutex` or single-threaded dispatcher rather than
  relying on `Dispatchers.IO` alone. Use `java.nio.file.Files.move` with
  `StandardCopyOption.ATOMIC_MOVE` where the target filesystem supports it
  for the `rename` port, and fall back to the same move-remove-move sequence
  this source uses when it does not, since `ATOMIC_MOVE` throws rather than
  completing when the underlying filesystem cannot guarantee it. Port the
  `FileType` bitmask as a Kotlin value class or `Int` constants with the same
  raw values (1, 2, 64) so a union like 65/66 round-trips identically for any
  caller comparing raw values across platforms.
- **React/Web**: There is no direct file-system access from a browser
  context; where this runs inside an Electron-style host with Node's `fs`
  module available, port to seven `async function`s returning `Promise`s,
  using `fs.promises.readFile`, `fs.promises.readdir` with
  `withFileTypes: true`, `fs.promises.lstat` for the non-following `stat`
  port (Node's `lstat` mirrors this component's `stat-does-not-follow-
  terminal-link` requirement directly, while `fs.promises.stat` would follow
  the link and need to be avoided here), `fs.promises.writeFile`,
  `fs.promises.mkdir` with `{ recursive: true }`, `fs.promises.rm`, and
  `fs.promises.rename` for the non-conflicting move, falling back to the
  same remove-then-rename-again sequence this source uses when the
  destination is occupied and `overwrite` is `true`, since Node's `rename`
  fails outright on a non-empty directory destination the same way
  `rename(2)` does. Route deletions through Electron's `shell.trashItem`
  when the `useTrash` port needs it, and treat any `errno` on the resulting
  `NodeJS.ErrnoException` (`ENOENT`, `EEXIST`, `EISDIR`, `ENOTDIR`,
  `ENOTEMPTY`, `EACCES`/`EPERM`) as the direct analogue of this component's
  POSIX-code classification (`error-classification-posix-first`).
- **AppKit / UIKit**: This recipe is extracted directly from Foundation,
  callable identically from an AppKit-hosted (macOS) or UIKit-hosted (iOS)
  caller; since `AgenticToolkitCore` is configured `platform: macOS` today,
  an iOS caller would first need the type made available to an iOS target,
  but the type itself needs no AppKit/UIKit-specific change to run there.
  The file system service is `FileSystemService` (`FileSystemService.swift`),
  declared as a Swift `actor` so its stored `queue` property and its seven
  operations are safe to call concurrently from any thread or `Task` with no
  additional synchronization at the call site (`concurrent-call-safety`).
  Each operation runs its blocking `FileManager` work on one private serial
  `DispatchQueue` (`qos: .userInitiated`) created once at `init()`, bridged
  back into the caller's `async` context via `withCheckedThrowingContinuation`
  in `perform(_:)`; every operation constructs its own fresh `FileManager()`
  inside its queued closure rather than capturing a shared instance, because
  `FileManager` is not `Sendable` (`fresh-file-manager-per-call`). The
  substitution interface is the `Sendable` protocol `FileSystemServicing`
  (`FileSystemServicing.swift`), which `FileSystemService` satisfies via an
  empty `extension` adding no code of its own
  (`servicing-conformance-is-free`). The file signature is the `Sendable`,
  `Equatable` `struct FileSignature` (`FileSignature.swift`) with
  `size: Int` and `modified: Date`; its `init?(of:)` derives both from
  `FileManager.default.attributesOfItem(atPath:)` rather than
  `url.resourceValues(forKeys:)` (`file-signature-stat-source`). The
  file-system error outcome is the `Error, LocalizedError` enum
  `FileSystemServiceError` (`FileSystemService.swift`), neither `Equatable`
  nor `Sendable` because its `noPermissions` case carries an `any Error`
  underlying cause; its cases are `fileNotFound`, `fileExists`,
  `fileIsADirectory`, `fileNotADirectory`, `directoryNotEmpty`,
  `noPermissions`, and the per-operation fallbacks `readFailed`,
  `writeFailed`, `statFailed`, `readDirectoryFailed`, `deleteFailed`,
  `renameFailed`, `createDirectoryFailed`; `errorDescription` returns one
  hardcoded English sentence per case via string interpolation, with no
  `NSLocalizedString` or `.strings` lookup. Classification
  (`distinguished(_:path:)`) checks a thrown error's POSIX code first via
  `posixCode(in:depth:)`, which walks a chain of `NSUnderlyingErrorKey`
  errors up to 4 levels, then falls back to the error's `CocoaError` code.
  The `FileType` bitmask uses raw values 1 (file), 2 (directory), 64
  (`symbolicLink`), with a link's own type unioned with its resolved
  target's bit where determinable (65 for a link to a file, 66 for a link
  to a directory) and `FileType.unknown` for a child whose type cannot be
  determined. `writeFile` writes via `Data.write(to:)` in place, never a
  temp-file-and-rename; `createDirectory` uses
  `FileManager.createDirectory(atPath:withIntermediateDirectories: true)`;
  `delete` uses `FileManager.trashItem(at:resultingItemURL: nil)` when
  `useTrash` is `true` and `FileManager.removeItem(at:)` otherwise;
  `rename` uses one `FileManager.moveItem(at:to:)` call, falling back to
  `FileManager.removeItem` then a retried `moveItem` when the destination is
  occupied and `overwrite` is `true`.
- **WinUI 3**: Port to a class exposing seven `async Task<T>` (or
  synchronous, for the parts that do not need to be awaited) equivalents,
  offloading each one's blocking work onto `Task.Run` as the counterpart to
  this component's dedicated `DispatchQueue` — bearing in mind, as with the
  sibling `VSIXInstaller` recipe's own WinUI note, that .NET's thread pool
  growing to accommodate blocking work makes the concern milder rather than
  absent. Use `System.IO.File`/`System.IO.Directory` members for `readFile`
  (`File.ReadAllBytesAsync`), `readDirectory`
  (`Directory.EnumerateFileSystemEntries` plus a per-entry `FileAttributes`
  check for the `FileType` bitmask port), and `writeFile`
  (`File.WriteAllBytesAsync`). `stat`'s non-following requirement
  (`stat-does-not-follow-terminal-link`) needs care on Windows: a plain
  `FileInfo`/`DirectoryInfo` follows a reparse point (the Windows analogue of
  a symbolic link) by default, so a faithful port must pass
  `FileOptions` or use `File.GetAttributes` with the `ReparsePoint` flag
  checked explicitly to answer the link's own attributes rather than its
  target's, mirroring what `lstat`-family calls give `stat(atPath:)` here.
  For `rename`'s overwrite sequence, use `Directory.Move`/`File.Move` for the
  non-conflicting path and the same move-remove-move-again sequence for the
  conflicting one, since `File.Move`/`Directory.Move` throw rather than
  atomically replace an existing destination — matching why this source
  needs the same three-step sequence rather than a single API call. Windows'
  own Recycle Bin has no first-party .NET API as of this writing, so a
  `useTrash` port typically needs `Microsoft.WindowsAPICodePack.Shell` or an
  equivalent shell-interop package rather than a framework type.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/FileSystem/` |

## Design Decisions

**Decision**: Give every operation its own fresh `FileManager()` inside its
queued closure, rather than sharing one `FileManager` instance across calls
or capturing `FileManager.default`.
**Rationale** (Swift/Foundation implementation): `FileManager` is not
`Sendable`; capturing a shared instance across the actor boundary and the
`DispatchQueue` closure would either not compile under strict concurrency or
require an unsafe escape, while a fresh, cheap instance per call keeps every
closure trivially `Sendable`-correct (`fresh-file-manager-per-call`).
**Approved**: pending

**Decision**: Attempt the rename operation's move first and act on the
overwrite flag only after that move fails as an already-exists outcome,
rather than checking whether the destination path is occupied before ever
attempting the move.
**Rationale**: A pre-check would make a case-only rename on a
case-insensitive volume, and a rename where the source and destination path
are identical, both report "already exists" for the very file being
renamed — the exact failure that would make renaming a file to fix its own
casing impossible. Attempting the move first lets those two cases succeed
outright, since the underlying move succeeds on them without ever
consulting the overwrite flag (`rename-destination-not-precchecked`,
`rename-case-only-and-self-renames-succeed`).
**Approved**: pending

**Decision**: Implement the rename operation's overwrite path as move,
remove, move again, guarded to reproduce the underlying move operation's
own `EISDIR`/`ENOTDIR`/`ENOTEMPTY` refusals, rather than as a single atomic
replace.
**Rationale** (Swift/Foundation implementation): Foundation has no API that
atomically replaces an occupied destination across both files and
directories. The doc comment records that an earlier hand-rolled version of
this sequence, without those guards, was strictly more destructive than the
`rename(2)` syscall it was meant to emulate — it would remove an occupying
directory that `rename(2)` itself would have refused to touch. The guarded
version accepts a narrower, explicitly documented failure window
(`rename-overwrite-failure-window`) instead of that broader, silent one.
**Approved**: pending

**Decision**: Route the delete operation's permanent-removal step, and the
removal inside the rename operation's overwrite sequence, through a direct
removal rather than through the Trash, even when the wider operation is one
a user might expect to be recoverable.
**Rationale**: The Trash option is the delete operation's own explicit,
caller-chosen flag; threading Trash semantics into a rename's internal
remove-then-replace step as well would silently change what "overwrite"
means for that call, and the Trash's renamed-on-collision behavior is not
something the `rename-overwrite-sequence` retry logic could correctly
account for.
**Approved**: pending

**Decision**: Report a read-directory child whose own type cannot be
determined with an unknown-type flag, rather than letting that one child's
failure abort or throw for the whole listing.
**Rationale**: A directory can contain an entry this process cannot stat —
a permission-denied child, or one that disappears between being listed and
being inspected — and treating that as fatal for every other, readable
child in the same directory would make an otherwise-successful listing
unusable because of one uninspectable entry
(`read-directory-unreadable-child-is-unknown`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | failed | Security |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | partial | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |

`separation-of-concerns` passes because `FileSystemService` does exactly one
job — translate seven `FileManager` operations into an `async`, actor-
isolated, typed-error API — and delegates everything else: `FileSignature`
owns change detection, `FileSystemServicing` owns the substitution seam, and
neither path safety nor workspace-root policy is this component's concern at
all (`Overview`).

`unit-test-coverage` passes on the strength of the 27 tests across
`FileSystemServiceTests.swift` and `FileSignatureTests.swift` traced into
`Conformance Test Vectors` above, covering every one of the seven operations'
success and failure paths, both `FileSignature` change-detection cases and
its documented blind spot, and a concurrency test exercising the shared
queue directly.

`explicit-error-handling` is partial: every operation surfaces a typed,
path-carrying `FileSystemServiceError` rather than swallowing a failure
silently, but `readDirectory`'s per-child type resolution
(`read-directory-unreadable-child-is-unknown`) deliberately converts an
unreadable child's failure into `FileType.unknown` instead of surfacing it
to the caller at all — a defensible choice, but one that means not every
failure the underlying `FileManager` calls can produce is actually reported.

`input-sanitization` fails: no operation validates, normalizes, or bounds
the `path`, `fromPath`, or `toPath` strings it is given in any way — no
traversal check, no containment check against any root, no rejection of an
absolute path where a relative one might be expected. The source is explicit
that this is by design (`Overview`: "it knows nothing about URIs,
workspaces, or extensions"), but the check itself asks whether input is
sanitized, and here it plainly is not; that responsibility is placed
entirely on the caller.

`fault-tolerance` is partial: most operations fail cleanly before writing
anything (`fileNotFound` before a write, `fileExists`/`directoryNotEmpty`
before a remove), but `writeFile` writes in place with no temporary-file
safety net (`write-file-not-atomic`), and `rename`'s overwrite sequence has
the accepted, documented data-loss window in `rename-overwrite-failure-
window` rather than a rollback.

`data-integrity` is partial for the same reason `fault-tolerance` is: the
`rename-overwrite-failure-window` case is a real, named scenario in which
this component permanently loses `toPath`'s prior contents on a plain
in-process failure, with no recovery attempt of its own; everywhere else,
data at rest is left exactly as an operation found it whenever that
operation fails.

`idempotent-operations` passes: `createDirectory` against an
already-existing directory succeeds silently rather than erroring
(`create-directory-idempotent`), and a rename onto the same path, or onto a
mere case variant of the same name, succeeds and leaves the file exactly
where it already was (`rename-case-only-and-self-renames-succeed`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to foundation/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
