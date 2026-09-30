<!-- leaf: implement-file-system/core-file-system--part-3 · source: file-system-core-file-system.md -->

# FileSystemService — continued (part 3)

**Rules** (cite as `implement-file-system/core-file-system--part-3#<slug>`):

- `create-directory-idempotent` MUST
- `create-directory-exists-error` MUST
- `delete-link-not-target` MUST
- `delete-not-found` MUST
- `delete-nonrecursive-emptiness-check` MUST
- `delete-recursive-flag-scope` MUST
- `delete-trash-flag` MUST
- `delete-trash-location-not-surfaced` MUST
- `rename-is-one-move` MUST
- `rename-source-not-found` MUST
- `rename-destination-not-precchecked` MUST
- `rename-case-only-and-self-renames-succeed` MUST
- `rename-overwrite-refusal` MUST
- `rename-overwrite-guards` MUST
- `rename-overwrite-sequence` MUST
- `rename-overwrite-failure-window` MUST
- `rename-hard-link-and-inode-identity` MUST
- `servicing-protocol-mirrors-actor` MUST
- `servicing-conformance-is-free` MUST
- `error-classification-posix-first` MUST
- `error-classification-chain-depth-bound` MUST
- `error-classification-fallback` MUST
- `permission-detection-best-effort` MUST

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
