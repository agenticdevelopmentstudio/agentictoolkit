---
id: 016f5ba0-f4ee-4b39-b1a2-83629768acdd
title: FileSystemService
domain: agentictoolkit://cookbook/core/file-system
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Seven async FileManager operations on one actor-owned serial queue, a typed
  FileSystemServiceError, and FileSignature's size-and-date change check.
platforms:
- swift
- macos
tags:
- filesystem
- actor
- concurrency
- foundation
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/extensions/host
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/main-thread-workspace
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

`FileSystemService` is the one place in AgenticToolkit that touches the real
file system on the caller's behalf. It is a plain `actor` wrapping
`FileManager` behind seven `async throws` operations — `readFile`,
`readDirectory`, `stat`, `writeFile`, `createDirectory`, `delete`, and
`rename` — each running its blocking `FileManager` work on one private serial
`DispatchQueue` and bridging back to the caller with
`withCheckedThrowingContinuation`. It knows nothing about URIs, workspaces, or
extensions; a caller holding a `URL` converts to a path string before calling
in, and `MainThreadWorkspace` is documented as the sole caller today, using it
as the concrete engine behind VS Code's `vscode.workspace.fs` surface.

Alongside it, `FileSignature` is an unrelated but co-located value type: a
cheap `size`-and-`modified` pair used to answer "has this file changed?"
without reading its bytes. `FileSystemServicing` is a matching protocol that
exists solely so a test double can stand in for the actor.

Every operation classifies its own failures into one `FileSystemServiceError`
case — trying a thrown error's POSIX code first, then its `CocoaError` code —
so a caller gets `fileNotFound`, `fileExists`, `fileIsADirectory`,
`fileNotADirectory`, `directoryNotEmpty`, or `noPermissions` where the source
can tell, and an operation-shaped fallback (`readFailed`, `writeFailed`,
`statFailed`, `readDirectoryFailed`, `deleteFailed`, `renameFailed`,
`createDirectoryFailed`) carrying the original error otherwise.

## Behavioral Requirements

- **file-signature-shape**: `FileSignature` MUST be a `Sendable`,
  `Equatable` `struct` with exactly two stored properties, `size: Int` and
  `modified: Date`, constructible directly via `init(size:modified:)`
  (`FileSignature.swift`).
- **file-signature-stat-source**: `FileSignature.init?(of:)` MUST derive
  `size` and `modified` from `FileManager.default.attributesOfItem(atPath:)`,
  never from `url.resourceValues(forKeys:)`, because a `URL` caches resource
  values it has already been asked for and a second signature taken from the
  same `URL` value would repeat the first one's numbers regardless of what
  changed on disk (`FileSignature.swift`, doc comment on `init?(of:)`).
- **file-signature-absence-is-nil**: `FileSignature.init?(of:)` MUST answer
  `nil`, not throw, when nothing can be stat'd at `url` — no such file, no
  permission, or a path that does not resolve to a file — leaving the caller
  to decide what absence means (`FileSignature.swift`; test
  `anAbsentFileHasNone`).
- **file-signature-equality-limit**: `FileSignature` equality MUST compare
  only `size` and `modified`; a rewrite that lands on the same byte count and
  the same modification date is indistinguishable from no change at all, and
  this is documented as the type's known limit rather than treated as a
  defect (`FileSignature.swift`; test `anIdenticallyStampedRewriteIsMissed`).
- **error-type-shape**: `FileSystemServiceError` MUST be an `Error,
  LocalizedError` enum, neither `Equatable` nor `Sendable`, because at least
  one case (`noPermissions`) carries an `any Error` underlying cause a caller
  may need to branch on directly rather than through `localizedDescription`
  (`FileSystemService.swift`).
- **error-cases-name-a-path**: Every case of `FileSystemServiceError` MUST
  carry the `path: String` (and, for `renameFailed`, also `destination:
  String`) that the failing operation was called with, so a caught error
  names the location it applies to (`FileSystemService.swift`).
- **error-description-fixed-strings**: `FileSystemServiceError.
  errorDescription` MUST return one hardcoded English sentence per case,
  built by string interpolation, with no `NSLocalizedString` or `.strings`
  lookup of any kind (`FileSystemService.swift`, `errorDescription`).
- **actor-isolation**: `FileSystemService` MUST be declared as an `actor`,
  so its stored `queue` property and its operations are safe to call
  concurrently from any thread or `Task` with no additional synchronization
  at the call site (`FileSystemService.swift`).
- **serial-queue-backing**: `FileSystemService` MUST run every one of its
  seven operations' blocking `FileManager` work on one private, serial
  `DispatchQueue` (`qos: .userInitiated`), created once at `init()` and never
  replaced (`FileSystemService.swift`, `queue` property).
- **continuation-bridge**: `perform(_:)` MUST bridge the queue's synchronous,
  throwing closure back into the caller's `async` context with
  `withCheckedThrowingContinuation`, so the calling `Task` suspends rather
  than blocking a cooperative-pool thread while the closure runs on the queue
  (`FileSystemService.swift`, `perform(_:)`).
- **calls-serialize-on-the-queue**: Two or more calls into the same
  `FileSystemService` instance MUST be served in the order their closures
  are enqueued onto that instance's single `DispatchQueue`, never interleaved
  with each other at a sub-call granularity (`FileSystemService.swift`; test
  `overlappingReadsDoNotMixUpTheirResults`, which runs eight concurrent reads
  and checks each returns its own correct payload).
- **fresh-file-manager-per-call**: Every operation MUST construct its own
  `FileManager()` inside its queued closure rather than capturing a shared
  instance, because `FileManager` is not `Sendable` and this keeps a
  non-`Sendable` object from ever crossing the queue boundary
  (`FileSystemService.swift`, every operation body).
- **independent-instances**: `FileSystemService.init()` MUST take no
  parameters and own no state beyond its own queue, so multiple instances may
  coexist, each with its own independent serial queue and no ordering
  guarantee between them (`FileSystemService.swift`, `init()` doc comment).
- **read-file-follows-links**: `readFile(atPath:)` MUST follow a symbolic
  link at `path` to its target's bytes, as reading a file always does
  (`FileSystemService.swift`, `readFile(atPath:)` doc comment).
- **read-file-not-found**: `readFile(atPath:)` MUST throw
  `FileSystemServiceError.fileNotFound(path:)` when nothing resolves at
  `path`, including a dangling symbolic link (`FileSystemService.swift`;
  test `readingAMissingFileReportsFileNotFound`).
- **read-file-is-a-directory**: `readFile(atPath:)` MUST throw
  `FileSystemServiceError.fileIsADirectory(path:)` when `path` resolves to a
  directory (`FileSystemService.swift`; test
  `readingADirectoryReportsFileIsADirectory`).
- **read-file-exact-bytes**: `readFile(atPath:)` MUST answer exactly the
  bytes on disk at `path`, with no transformation (`FileSystemService.swift`;
  test `readFileAnswersTheBytesOnDisk`).
- **read-directory-entry-shape**: `readDirectory(atPath:)` MUST answer one
  `DirectoryEntry(name:type:)` per child of `path`, where `name` is the
  child's own last path component and `type` is its `FileType` bitmask; the
  listing MUST NOT be recursive (`FileSystemService.swift`,
  `readDirectory(atPath:)`; test `readDirectoryAnswersEveryChildWithItsType`).
- **read-directory-follows-link**: `readDirectory(atPath:)` MUST follow a
  symbolic link at `path` and list the directory it points to before
  enumerating children (`FileSystemService.swift`; test
  `readDirectoryFollowsALinkToADirectory`).
- **read-directory-not-a-directory**: `readDirectory(atPath:)` MUST throw
  `FileSystemServiceError.fileNotADirectory(path:)` when `path` does not
  resolve to a directory (`FileSystemService.swift`; test
  `listingAFileReportsFileNotADirectory`).
- **read-directory-unreadable-child-is-unknown**: `readDirectory(atPath:)`
  MUST report a child whose own type cannot be determined as `FileType.
  unknown` rather than aborting or throwing for that one child, while a
  failure to read `path` itself still throws (`FileSystemService.swift`,
  `prefetchedTypeBits(of:using:)`).
- **read-directory-link-child-union-bits**: A child that is a symbolic link
  MUST be reported with the union of `FileType.symbolicLink` and its
  resolved target's type bit where the target's type can be determined —
  raw value 65 for a link to a file, 66 for a link to a directory, the
  `symbolicLink` bit alone when the target is gone — never `symbolicLink`
  alone for a resolvable target (`FileSystemService.swift`,
  `prefetchedTypeBits(of:using:)`; test
  `readDirectoryAnswersEveryChildWithItsType`, asserting the link entry's raw
  value is 65).
- **stat-does-not-follow-terminal-link**: `stat(atPath:)` MUST NOT follow a
  terminal symbolic link at `path`; it MUST report the link's own type,
  timestamps, and size, not its target's (`FileSystemService.swift`,
  `stat(atPath:)` doc comment; test `statReportsTheLinksOwnSize`).
- **stat-link-target-bit-union**: `stat(atPath:)` MUST set `FileType.
  symbolicLink` together with the resolved target's own type bit where that
  can be determined cheaply — raw value 65 for a link to a file, 66 for a
  link to a directory — and `symbolicLink` alone when the target does not
  exist (`FileSystemService.swift`; tests
  `statOfALinkToAFileAnswersBothBits`,
  `statOfALinkToADirectoryAnswersBothBits`,
  `statOfADanglingLinkAnswersTheLinkBit`).
- **stat-optional-timestamps**: `FileStat.creationDate` and `FileStat.
  modificationDate` MUST each be `nil` when `FileManager` does not report
  that attribute, never coerced to a placeholder date
  (`FileSystemService.swift`, `FileStat` struct).
- **stat-size-fallback**: `FileStat.size` MUST fall back to `0` when
  `FileManager` does not report a size attribute
  (`FileSystemService.swift`, `FileStat.init`).
- **stat-missing-path**: `stat(atPath:)` MUST throw `FileSystemServiceError.
  fileNotFound(path:)` when nothing is at `path` (`FileSystemService.swift`;
  test `stattingAMissingPathReportsFileNotFound`).
- **write-file-create-flag**: `writeFile(atPath:contents:create:overwrite:)`
  MUST throw `FileSystemServiceError.fileNotFound(path:)`, writing nothing,
  when nothing exists at `path` and `create` is `false`; it MUST write and
  create `path` when `create` is `true` (`FileSystemService.swift`; tests
  `writingWithoutCreateRefusesAMissingPath`,
  `writingWithCreateWritesAMissingPath`).
- **write-file-overwrite-flag**:
  `writeFile(atPath:contents:create:overwrite:)` MUST throw
  `FileSystemServiceError.fileExists(path:)`, leaving the existing bytes
  untouched, when something already exists at `path` and `overwrite` is
  `false`; it MUST replace the bytes when `overwrite` is `true`
  (`FileSystemService.swift`; tests
  `writingWithoutOverwriteRefusesAnExistingFile`,
  `writingWithOverwriteReplacesAnExistingFile`).
- **write-file-onto-directory**:
  `writeFile(atPath:contents:create:overwrite:)` MUST throw
  `FileSystemServiceError.fileIsADirectory(path:)` when `path` resolves to a
  directory, regardless of the flags (`FileSystemService.swift`; test
  `writingOntoADirectoryReportsFileIsADirectory`).
- **write-file-existence-at-the-link**: `writeFile`'s existence check MUST
  be judged at the link, not through it, so a dangling symbolic link at
  `path` counts as something already there for the `overwrite` check
  (`FileSystemService.swift`, `writeFile` doc comment).
- **write-file-not-atomic**:
  `writeFile(atPath:contents:create:overwrite:)` MUST write `contents` in
  place with `Data.write(to:)`, never via a temporary file renamed over the
  destination, so an existing file's inode and permissions are preserved and
  a write through a symbolic link lands on the link's target rather than
  replacing the link itself (`FileSystemService.swift`, `writeFile` doc
  comment).
- **create-directory-with-parents**: `createDirectory(atPath:)` MUST create
  `path` and every missing intermediate parent directory in one call
  (`FileSystemService.swift`; test
  `createDirectoryCreatesTheDirectoryAndItsParents`).
- **create-directory-idempotent**: `createDirectory(atPath:)` MUST succeed
  with no error when `path` already resolves to a directory
  (`FileSystemService.swift`, `createDirectory` doc comment).
- **create-directory-exists-error**: `createDirectory(atPath:)` MUST throw
  `FileSystemServiceError.fileExists(path:)` when something that is not a
  directory already exists at `path` (`FileSystemService.swift`; test
  `creatingADirectoryOverAFileReportsFileExists`).
- **delete-link-not-target**: `delete(atPath:recursive:useTrash:)` MUST
  delete a symbolic link at `path` as the link itself, leaving its target
  untouched (`FileSystemService.swift`; test
  `deletingASymbolicLinkLeavesItsTarget`).
- **delete-not-found**: `delete(atPath:recursive:useTrash:)` MUST throw
  `FileSystemServiceError.fileNotFound(path:)` when nothing is at `path`
  (`FileSystemService.swift`, `delete` implementation).
- **delete-nonrecursive-emptiness-check**:
  `delete(atPath:recursive: false:useTrash:)` MUST throw
  `FileSystemServiceError.directoryNotEmpty(path:)` and delete nothing when
  `path` is a directory with any entries in it; it MUST succeed when the
  directory has none (`FileSystemService.swift`; tests
  `deletingANonEmptyDirectoryWithoutRecursiveRefuses`,
  `deletingAnEmptyDirectoryWithoutRecursiveRemovesIt`).
- **delete-recursive-flag-scope**: The `recursive` flag's only effect MUST
  be the emptiness check above — `FileManager.removeItem(at:)` itself
  recurses unconditionally regardless of the flag, so `recursive: true`
  against a populated directory MUST remove it and its contents in one call
  (`FileSystemService.swift`, `delete` doc comment; test
  `deletingANonEmptyDirectoryRecursivelyRemovesIt`).
- **delete-trash-flag**: `delete(atPath:recursive:useTrash: true)` MUST
  move the item to the user's Trash via `FileManager.trashItem(at:
  resultingItemURL:)` instead of permanently removing it; `useTrash: false`
  MUST permanently remove it via `FileManager.removeItem(at:)`
  (`FileSystemService.swift`; test
  `deletingThroughTheTrashMovesTheItemThere`).
- **delete-trash-location-not-surfaced**:
  `delete(atPath:recursive:useTrash:)` MUST NOT report where a trashed item
  landed — `trashItem` is called with `resultingItemURL: nil` — because the
  Trash may rename an item to avoid a collision and no member of this type
  answers that renamed location (`FileSystemService.swift`, `delete` doc
  comment).
- **rename-is-one-move**: `rename(fromPath:toPath:overwrite:)` MUST treat
  rename and move as the same single operation, backed by one
  `FileManager.moveItem(at:to:)` call on the non-conflicting path
  (`FileSystemService.swift`, `rename` doc comment; test
  `renameMovesTheItem`).
- **rename-source-not-found**: `rename(fromPath:toPath:overwrite:)` MUST
  throw `FileSystemServiceError.fileNotFound(path: fromPath)`, leaving
  `toPath` untouched, when nothing is at `fromPath`
  (`FileSystemService.swift`; test
  `renamingFromAMissingPathReportsFileNotFound`).
- **rename-destination-not-precchecked**:
  `rename(fromPath:toPath:overwrite:)` MUST NOT pre-check whether `toPath`
  is occupied before attempting the move; it MUST attempt the move first
  and act on `overwrite` only after that move fails in a way classified as
  `fileExists` (`FileSystemService.swift`, `rename` doc comment).
- **rename-case-only-and-self-renames-succeed**: A rename that only changes
  the case of a name on a case-insensitive volume, and a rename where
  `fromPath == toPath`, MUST succeed regardless of the `overwrite` value,
  because the underlying move succeeds outright and `overwrite` is never
  consulted on that path (`FileSystemService.swift`, `rename` doc comment;
  tests `renamingOnlyTheCaseKeepsTheFile`,
  `renamingOnlyTheCaseSucceedsWithoutOverwrite`,
  `renamingAPathOntoItselfKeepsTheFile`).
- **rename-overwrite-refusal**: `rename(fromPath:toPath:overwrite: false)`
  MUST throw `FileSystemServiceError.fileExists(path: toPath)` and move
  nothing when the move fails because a distinct item already occupies
  `toPath` (`FileSystemService.swift`; test
  `renamingOntoAnExistingPathRefuses`).
- **rename-overwrite-guards**: `rename(fromPath:toPath:overwrite: true)`,
  before removing an occupied `toPath`, MUST reproduce `rename(2)`'s own
  three refusals: `FileSystemServiceError.fileIsADirectory(path: toPath)`
  for a non-directory source onto a directory destination,
  `FileSystemServiceError.fileNotADirectory(path: toPath)` for the reverse,
  and `FileSystemServiceError.directoryNotEmpty(path: toPath)` for a
  directory destination that has entries in it (`FileSystemService.swift`,
  `rename` doc comment).
- **rename-overwrite-sequence**: `rename(fromPath:toPath:overwrite: true)`
  onto a genuinely occupied destination MUST proceed as move, remove, move
  again — attempt the move, remove the occupying item once the guards above
  clear it, then retry the move — never a single atomic replace, because
  Foundation offers no API that atomically replaces a destination spanning
  files and directories alike (`FileSystemService.swift`, `rename` doc
  comment; test `renamingOntoAnExistingPathWithOverwriteReplacesIt`).
- **rename-overwrite-failure-window**: If the removal step of
  `rename-overwrite-sequence` succeeds but the retried move then fails,
  `toPath`'s former contents MUST be gone with nothing put back, `fromPath`
  MUST still be in place, and the caller MUST receive
  `FileSystemServiceError.renameFailed(path:destination:underlying:)` — this
  window is a documented, accepted risk of the sequence, not a defect the
  source attempts to close (`FileSystemService.swift`, `rename` doc comment:
  "It does have the other window, and it destroys data.").
- **rename-hard-link-and-inode-identity**:
  `rename(fromPath:toPath:overwrite:)` MUST rely on `FileManager.moveItem`
  and `FileManager.removeItem` to distinguish a hard link from a case-only
  alias, rather than comparing paths, folded case, or device/inode numbers
  itself, because either of those comparisons is indistinguishable from a
  legitimate rename the caller is entitled to make
  (`FileSystemService.swift`, `rename` doc comment; test
  `renamingOntoAHardLinkReplacesTheOtherName`).
- **servicing-protocol-mirrors-actor**: `FileSystemServicing` MUST declare
  exactly the seven operations `FileSystemService` exposes, with identical
  signatures, and MUST be declared `Sendable` (`FileSystemServicing.swift`).
- **servicing-conformance-is-free**: `FileSystemService` MUST conform to
  `FileSystemServicing` via an empty `extension`, adding no code of its own,
  because every required member is already implemented with a matching
  signature (`FileSystemServicing.swift`).
- **error-classification-posix-first**: `FileSystemServiceError.
  distinguished(_:path:)` MUST check a thrown error's POSIX code before
  consulting its `CocoaError` code, because the two independently-observed
  routes to a move failure surface the errno first
  (`FileSystemService.swift`, `distinguished(_:path:)`, `rename` doc
  comment).
- **error-classification-chain-depth-bound**: `posixCode(in:depth:)` MUST
  stop searching an error's chain of `NSUnderlyingErrorKey` errors after 4
  levels, as a guard against a cyclic chain rather than a claim about how
  deep Foundation nests errors (`FileSystemService.swift`,
  `posixCode(in:depth:)`).
- **error-classification-fallback**: When `distinguished(_:path:)`
  recognizes nothing in a thrown error, every operation MUST fall back to
  its own operation-shaped error case carrying the original error as
  `underlying` (`FileSystemService.swift`, every operation body).
- **permission-detection-best-effort**: `FileSystemServiceError.
  noPermissions` detection MUST be best-effort — it fires only when a
  Foundation `CocoaError` names a permission-specific code or an `EACCES`/
  `EPERM` is reachable in the error's chain; a permission failure surfaced
  any other way MUST arrive as the calling operation's own
  operation-shaped fallback case instead (`FileSystemService.swift`,
  `noPermissions` doc comment).
- **concurrent-instance-ordering**: No lock, actor, or ordering rule spans two independently-constructed `FileSystemService` instances, or an external process, operating against the same `path` concurrently; each instance's own serial queue orders only its own calls, so `writeFile`'s existence check and write, `createDirectory`'s existence check and create, and `delete`'s emptiness check and removal are each atomic only relative to that one instance's queue, never relative to a second instance or process racing the same path in between (`FileSystemService.swift`; corroborated by `MainThreadWorkspace`, which requires every extension to share one `FileSystemService` instance for exactly this reason).

## Appearance

Not applicable — this is a file-system service, not a visual component.

## States

Not applicable — this is a file-system service, not a visual component.

## Accessibility

Not applicable — this is a file-system service, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| file-system-001 | file-signature-shape, file-signature-stat-source | `FileSignature(of: file)` twice in a row against an untouched 8-byte file | Both signatures are equal; `first.size == 8` (test `anUntouchedFileIsUnchanged`) |
| file-system-002 | file-signature-equality-limit | `FileSignature(of: file)` before and after a rewrite that changes both length and modification date | The two signatures are unequal (test `aRewriteIsNoticed`) |
| file-system-003 | file-signature-equality-limit | `FileSignature(of: file)` before and after a rewrite pinned to the same `modificationDate` as the original | The two signatures are equal, by design (test `anIdenticallyStampedRewriteIsMissed`) |
| file-system-004 | file-signature-absence-is-nil | `FileSignature(of: url)` for a `url` naming nothing on disk | Returns `nil`, no throw (test `anAbsentFileHasNone`) |
| file-system-005 | read-file-exact-bytes | `readFile(atPath:)` against a file whose bytes are known | Returns exactly those bytes (test `readFileAnswersTheBytesOnDisk`) |
| file-system-006 | read-file-not-found | `readFile(atPath:)` against a path with nothing there | Throws `FileSystemServiceError.fileNotFound(path:)` (test `readingAMissingFileReportsFileNotFound`) |
| file-system-007 | read-file-is-a-directory | `readFile(atPath:)` against a directory path | Throws `FileSystemServiceError.fileIsADirectory(path:)` (test `readingADirectoryReportsFileIsADirectory`) |
| file-system-008 | read-directory-entry-shape, read-directory-link-child-union-bits | `readDirectory(atPath:)` against a directory holding a plain file, a subdirectory, and a symbolic link to the file | Answers one entry per child; the link entry's `type.rawValue == 65` (test `readDirectoryAnswersEveryChildWithItsType`) |
| file-system-009 | read-directory-follows-link | `readDirectory(atPath:)` against a path that is itself a symbolic link to a directory | Lists the target directory's children (test `readDirectoryFollowsALinkToADirectory`) |
| file-system-010 | read-directory-not-a-directory | `readDirectory(atPath:)` against a plain file's path | Throws `FileSystemServiceError.fileNotADirectory(path:)` (test `listingAFileReportsFileNotADirectory`) |
| file-system-011 | stat-does-not-follow-terminal-link, stat-link-target-bit-union | `stat(atPath:)` against a symbolic link to a file, a symbolic link to a directory, and a dangling symbolic link | Raw `type` values `65`, `66`, and `64` respectively (tests `statOfALinkToAFileAnswersBothBits`, `statOfALinkToADirectoryAnswersBothBits`, `statOfADanglingLinkAnswersTheLinkBit`) |
| file-system-012 | stat-does-not-follow-terminal-link | `stat(atPath:)` against a symbolic link whose own path string is shorter than its target's contents | `size` equals the link's own path-string byte length, not the target's size (test `statReportsTheLinksOwnSize`) |
| file-system-013 | stat-missing-path | `stat(atPath:)` against a path with nothing there | Throws `FileSystemServiceError.fileNotFound(path:)` (test `stattingAMissingPathReportsFileNotFound`) |
| file-system-014 | write-file-create-flag | `writeFile(atPath:contents:create: false:overwrite:)` against a missing path | Throws `FileSystemServiceError.fileNotFound(path:)`, writes nothing (test `writingWithoutCreateRefusesAMissingPath`) |
| file-system-015 | write-file-create-flag | `writeFile(atPath:contents:create: true:overwrite:)` against a missing path | Succeeds; the path now holds `contents` (test `writingWithCreateWritesAMissingPath`) |
| file-system-016 | write-file-overwrite-flag | `writeFile(atPath:contents:create:overwrite: false)` against an existing file | Throws `FileSystemServiceError.fileExists(path:)`, leaves the original bytes (test `writingWithoutOverwriteRefusesAnExistingFile`) |
| file-system-017 | write-file-overwrite-flag | `writeFile(atPath:contents:create:overwrite: true)` against an existing file | Succeeds; the path now holds the new `contents` (test `writingWithOverwriteReplacesAnExistingFile`) |
| file-system-018 | write-file-onto-directory | `writeFile(atPath:contents:create:overwrite:)` against a directory path | Throws `FileSystemServiceError.fileIsADirectory(path:)` (test `writingOntoADirectoryReportsFileIsADirectory`) |
| file-system-019 | create-directory-with-parents | `createDirectory(atPath:)` against a path several missing intermediate levels deep | Succeeds; `path` and every missing parent now exist (test `createDirectoryCreatesTheDirectoryAndItsParents`) |
| file-system-020 | create-directory-exists-error | `createDirectory(atPath:)` against a path already occupied by a plain file | Throws `FileSystemServiceError.fileExists(path:)` (test `creatingADirectoryOverAFileReportsFileExists`) |
| file-system-021 | delete-nonrecursive-emptiness-check | `delete(atPath:recursive: false:useTrash: false)` against a directory holding one entry, then against an emptied copy of the same directory | The populated case throws `FileSystemServiceError.directoryNotEmpty(path:)`; the empty case succeeds (tests `deletingANonEmptyDirectoryWithoutRecursiveRefuses`, `deletingAnEmptyDirectoryWithoutRecursiveRemovesIt`) |
| file-system-022 | delete-recursive-flag-scope | `delete(atPath:recursive: true:useTrash: false)` against a directory holding several entries | Succeeds; the directory and every entry in it are gone (test `deletingANonEmptyDirectoryRecursivelyRemovesIt`) |
| file-system-023 | delete-trash-flag | `delete(atPath:recursive:useTrash: true)` against an ordinary file | The file is no longer at `path`; it is reachable through the user's Trash rather than permanently removed (test `deletingThroughTheTrashMovesTheItemThere`) |
| file-system-024 | delete-link-not-target | `delete(atPath:recursive:useTrash:)` against a symbolic link to a file that still needs to exist afterward | The link is gone; the file it pointed to still exists with its original contents (test `deletingASymbolicLinkLeavesItsTarget`) |
| file-system-025 | rename-case-only-and-self-renames-succeed | `rename(fromPath: "Name.txt", toPath: "name.txt", overwrite: false)` on a case-insensitive volume | Succeeds; the file still exists under the new casing (tests `renamingOnlyTheCaseKeepsTheFile`, `renamingOnlyTheCaseSucceedsWithoutOverwrite`) |
| file-system-026 | rename-case-only-and-self-renames-succeed | `rename(fromPath: path, toPath: path, overwrite: false)` | Succeeds; the file is unchanged (test `renamingAPathOntoItselfKeepsTheFile`) |
| file-system-027 | rename-overwrite-refusal | `rename(fromPath:toPath:overwrite: false)` where `toPath` already names a distinct file | Throws `FileSystemServiceError.fileExists(path: toPath)`, moves nothing (test `renamingOntoAnExistingPathRefuses`) |
| file-system-028 | rename-overwrite-sequence | `rename(fromPath:toPath:overwrite: true)` where `toPath` already names a distinct file | Succeeds; `toPath` now holds `fromPath`'s former contents, `fromPath` no longer exists (test `renamingOntoAnExistingPathWithOverwriteReplacesIt`) |
| file-system-029 | rename-hard-link-and-inode-identity | `rename(fromPath:toPath:overwrite: true)` where `toPath` is a hard link to a different name for the very inode already at `fromPath`'s eventual destination shape | The other name is replaced correctly rather than treated as identical to `fromPath` (test `renamingOntoAHardLinkReplacesTheOtherName`) |
| file-system-030 | calls-serialize-on-the-queue | Eight concurrent `readFile(atPath:)` calls into one `FileSystemService` instance, each against a different file with distinct contents | Each caller's `await` returns exactly its own file's bytes, with none mixed up (test `overlappingReadsDoNotMixUpTheirResults`) |

## Edge Cases

- **Null and empty input**: `readFile`, `readDirectory`, `stat`, `delete`,
  and both sides of `rename` all treat an empty `path` string the same way
  they treat any other path nothing resolves at: `FileManager` reports it as
  absent, and the operation throws its `fileNotFound`/`fileNotADirectory`-
  shaped case rather than a distinct "empty path" error, since no case in
  `FileSystemServiceError` singles that condition out
  (`FileSystemService.swift`). `writeFile` with zero-length `contents` MUST
  still create or replace the file — an empty file is a valid outcome, not
  an error — since `Data.write(to:)` places no minimum-length requirement on
  its argument.
- **Boundary values**: `readDirectory` against a directory with zero
  children MUST answer an empty array, not throw, since `contentsOfDirectory
  (atPath:)` succeeds on an empty directory the same way it does on a
  populated one. A `path` that is a symbolic link chain terminating in
  another symbolic link (rather than a file or directory) is not addressed
  by any operation's doc comment; `stat` still reports the first link's own
  type without walking further, per `stat-does-not-follow-terminal-link`,
  while `readFile`/`readDirectory`'s `follow-links` requirements resolve the
  whole chain because that is what `FileManager`'s own path-based read APIs
  do.
- **Concurrent access**: Per `concurrent-instance-ordering`, two `FileSystemService` instances, or
  this actor and an external process, racing the same `path` have no
  ordering, mutual exclusion, or overlap detection between them; each
  instance's serial queue only orders its own calls
  (`calls-serialize-on-the-queue` establishes that narrower guarantee, and no
  requirement here claims more).
- **Error states**: `rename`'s overwrite path
  (`rename-overwrite-sequence`) has a genuine, documented failure window —
  `rename-overwrite-failure-window` — where a successful removal of the
  occupying item followed by a failed retry move permanently loses that
  item's former contents; the source states this plainly rather than
  claiming a rollback it does not perform. Every other operation's failure
  modes are either a clean refusal before anything is written (`fileNotFound`
  before a write, `fileExists`/`directoryNotEmpty` before a remove) or a
  best-effort classification (`permission-detection-best-effort`) that falls
  back to an operation-shaped error rather than misreporting the cause.
- **Offline / disconnected state**: Not applicable — every operation acts
  on a local file-system path with `FileManager`; none of the three source
  files reference a network call, `URLSession`, or any remote dependency
  whose availability could vary.
- **Crash / power-loss recovery**: Not addressed by the source at all —
  `writeFile` writes in place (`write-file-not-atomic`) with no journal,
  temp file, or fsync barrier of its own, and `rename`'s overwrite sequence
  performs its remove-then-move-again steps with no on-disk marker that
  would let a later call detect and finish an interruption between them the
  way a recovery sweep would. A power loss between the removal and the
  retried move in `rename-overwrite-sequence` leaves exactly the state
  `rename-overwrite-failure-window` already documents as a live risk of an
  ordinary in-process failure at that same point — this component treats
  that window as accepted, not recoverable.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `path` (`readFile`, `readDirectory`, `stat`, `createDirectory`) | `String` | none (required) | The file-system location the operation acts on; not a `URL`, so a caller converts before calling in. |
| `fromPath`, `toPath` (`rename`) | `String` | none (required) | The source and destination paths for the one `moveItem`-backed move. |
| `path` (`delete`) | `String` | none (required) | The file-system location to remove or move to the Trash. |
| `contents` (`writeFile`) | `Data` | none (required) | The exact bytes written to `path`; never appended to or chunked. |
| `create` (`writeFile`) | `Bool` | none (required) | When `true`, a missing `path` is created; when `false`, a missing `path` throws `fileNotFound`. |
| `overwrite` (`writeFile`) | `Bool` | none (required) | When `true`, an existing `path` is replaced; when `false`, an existing `path` throws `fileExists`. Independent of `create`. |
| `recursive` (`delete`) | `Bool` | none (required) | When `false`, a non-empty directory throws `directoryNotEmpty`; the removal itself always recurses once it proceeds. |
| `useTrash` (`delete`) | `Bool` | none (required) | `true` routes through `FileManager.trashItem`; `false` permanently removes via `FileManager.removeItem`. |
| `overwrite` (`rename`) | `Bool` | none (required) | Governs only what happens when the initial move fails because something distinct already occupies `toPath`. |

`FileSystemService.init()` itself takes no parameters and exposes no
configurable state: each instance owns one private serial queue, fixed for
the instance's lifetime, and nothing about that queue's label, QoS, or
behavior is caller-adjustable.

## Deep Linking

Not applicable: `FileSystemService` operates on file-system paths, not app
URLs or navigation destinations, and defines no deep-link surface of its own
(traced to the full body of `FileSystemService.swift`, `FileSystemServicing.
swift`, and `FileSignature.swift`).

## Localization

Not applicable in the sense of user-facing display strings needing
translation infrastructure, but not ideal either:
`FileSystemServiceError.errorDescription` builds every one of its case
messages as a hardcoded English sentence via string interpolation, with no
`NSLocalizedString`, `.strings` table, or other localization lookup anywhere
in the source (`error-description-fixed-strings`). A caller that surfaces
`localizedDescription` directly in UI would show English text regardless of
the user's locale; `MainThreadWorkspace`, the one documented caller, is
itself recorded elsewhere as failing its own `no-hardcoded-strings` check for
passing these same strings through verbatim.

## Accessibility Options

Not applicable: this is a non-visual file-system service with no rendered
UI to respond to Reduce Motion, Increase Contrast, or Differentiate Without
Color (traced to the full source, which contains no UI code of any kind).

## Feature Flags

Not applicable: the source declares no feature-flag or remote-config lookup
of any kind — every one of the seven operations and `FileSignature`'s check
runs the same fixed logic unconditionally (traced to the absence of any flag
check anywhere in `FileSystemService.swift`, `FileSystemServicing.swift`, and
`FileSignature.swift`).

## Analytics

Not applicable: the source contains no event-emission or telemetry call of
any kind — an operation either returns its result or throws a
`FileSystemServiceError`, with no recorded event either way (traced to the
full body of all three source files).

## Privacy

- **Data collected**: `FileSystemService` collects nothing beyond the path
  strings and byte contents a caller already supplies as arguments; it reads
  no attribute beyond what each operation's own contract needs (type,
  timestamps, and size for `stat`; a directory listing's names and types for
  `readDirectory`). `FileSignature` reads only a file's size and modification
  date, never its contents.
- **Storage**: Every write, rename, and directory creation lands as ordinary,
  unencrypted files or directories at whatever path the caller names — this
  component applies no encryption, sandboxing, or access-control policy of
  its own, and relies entirely on the OS and the calling app's own sandbox
  entitlements for what paths are actually reachable.
- **Transmission**: Not applicable — nothing in `FileSystemService.swift`,
  `FileSystemServicing.swift`, or `FileSignature.swift` makes a network call
  of any kind; every operation is local-disk-only.
- **Retention**: `FileSystemService` sets no retention or expiry policy of
  its own; a written or renamed item persists until a caller deletes it, and
  a `delete(atPath:recursive:useTrash: true)` call moves an item to the
  user's Trash rather than erasing it immediately, extending its retention
  under the OS's own Trash lifecycle rather than this component's.
- **Path strings may be sensitive**: Every `FileSystemServiceError` case
  interpolates the caller-supplied `path` verbatim into its
  `errorDescription` (`error-description-fixed-strings`); on a typical
  macOS install that path routinely contains the user's account name (for
  example, under `/Users/<name>/`), so a caller that logs or displays a
  caught error's description unfiltered is exposing that path segment
  wherever the error surfaces.

## Logging

This component performs no logging of its own — no `os_log`, `print`,
`Logger`, or diagnostic breadcrumb of any kind appears anywhere in
`FileSignature.swift`, `FileSystemService.swift`, or
`FileSystemServicing.swift` (traced to the full body of all three files).
Every failure surfaces as a thrown, typed `FileSystemServiceError` instead of
a log line; a caller that wants a trail of what this component did must log
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
- **AppKit / UIKit**: No divergence from the SwiftUI bullet above — the
  source is framework-agnostic `Foundation` code, callable identically from
  an AppKit-hosted (macOS) or UIKit-hosted (iOS) caller. Since
  `AgenticToolkitCore` is configured `platform: macOS` today, an iOS caller
  would first need the type made available to an iOS target; the type itself
  needs no AppKit/UIKit-specific change to run there.
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
**Rationale**: `FileManager` is not `Sendable`; capturing a shared instance
across the actor boundary and the `DispatchQueue` closure would either not
compile under strict concurrency or require an unsafe escape, while a fresh,
cheap instance per call keeps every closure trivially `Sendable`-correct
(`fresh-file-manager-per-call`).
**Approved**: pending

**Decision**: Attempt `rename`'s move first and act on `overwrite` only
after that move fails as `fileExists`, rather than checking whether `toPath`
is occupied before ever attempting the move.
**Rationale**: A pre-check would make a case-only rename on a
case-insensitive volume, and a rename where `fromPath == toPath`, both
report "already exists" for the very file being renamed — the exact
failure that would make renaming a file to fix its own casing impossible.
Attempting the move first lets those two cases succeed outright, since the
underlying move succeeds on them without ever consulting `overwrite`
(`rename-destination-not-precchecked`, `rename-case-only-and-self-renames-
succeed`).
**Approved**: pending

**Decision**: Implement `rename`'s overwrite path as move, remove, move
again, guarded to reproduce `rename(2)`'s own `EISDIR`/`ENOTDIR`/
`ENOTEMPTY` refusals, rather than as a single atomic replace.
**Rationale**: Foundation has no API that atomically replaces an occupied
destination across both files and directories. The doc comment records that
an earlier hand-rolled version of this sequence, without those guards, was
strictly more destructive than the `rename(2)` syscall it was meant to
emulate — it would remove an occupying directory that `rename(2)` itself
would have refused to touch. The guarded version accepts a narrower,
explicitly documented failure window (`rename-overwrite-failure-window`)
instead of that broader, silent one.
**Approved**: pending

**Decision**: Route `delete`'s permanent-removal step, and the removal
inside `rename`'s overwrite sequence, through `FileManager.removeItem`
rather than through the Trash, even when the wider operation is one a user
might expect to be recoverable.
**Rationale**: `useTrash` is `delete`'s own explicit, caller-chosen flag;
threading Trash semantics into a rename's internal remove-then-replace step
as well would silently change what "overwrite" means for that call, and
`FileManager.trashItem`'s renamed-on-collision behavior is not something the
`rename-overwrite-sequence` retry logic could correctly account for.
**Approved**: pending

**Decision**: Report a `readDirectory` child whose own type cannot be
determined as `FileType.unknown`, rather than letting that one child's
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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
