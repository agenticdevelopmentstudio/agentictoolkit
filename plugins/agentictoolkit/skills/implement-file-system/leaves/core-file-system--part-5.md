<!-- leaf: implement-file-system/core-file-system--part-5 · source: file-system-core-file-system.md -->

# FileSystemService — continued (part 5)

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
