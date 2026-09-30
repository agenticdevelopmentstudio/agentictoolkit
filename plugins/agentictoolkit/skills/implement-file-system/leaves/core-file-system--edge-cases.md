<!-- leaf: implement-file-system/core-file-system--edge-cases · source: file-system-core-file-system.md -->

# FileSystemService

**Rules** (cite as `implement-file-system/core-file-system--edge-cases#<slug>`):

- `null-and-empty-input` MUST — readFile, readDirectory, stat, delete, and both sides of rename all treat an empty path string the same way they treat …
- `boundary-values` MUST — readDirectory against a directory with zero children MUST answer an empty array, not throw, since contentsOfDirectory …

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
