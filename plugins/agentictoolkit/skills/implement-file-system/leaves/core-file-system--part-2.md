<!-- leaf: implement-file-system/core-file-system--part-2 · source: file-system-core-file-system.md -->

# FileSystemService — continued (part 2)

**Rules** (cite as `implement-file-system/core-file-system--part-2#<slug>`):

- `file-signature-shape` MUST
- `file-signature-stat-source` MUST
- `file-signature-absence-is-nil` MUST
- `file-signature-equality-limit` MUST
- `error-type-shape` MUST
- `error-cases-name-a-path` MUST
- `error-description-fixed-strings` MUST
- `actor-isolation` MUST
- `serial-queue-backing` MUST
- `continuation-bridge` MUST
- `calls-serialize-on-the-queue` MUST
- `fresh-file-manager-per-call` MUST
- `independent-instances` MUST
- `read-file-follows-links` MUST
- `read-file-not-found` MUST
- `read-file-is-a-directory` MUST
- `read-file-exact-bytes` MUST
- `read-directory-entry-shape` MUST
- `read-directory-follows-link` MUST
- `read-directory-not-a-directory` MUST
- `read-directory-unreadable-child-is-unknown` MUST
- `read-directory-link-child-union-bits` MUST
- `stat-does-not-follow-terminal-link` MUST
- `stat-link-target-bit-union` MUST
- `stat-optional-timestamps` MUST
- `stat-size-fallback` MUST
- `stat-missing-path` MUST
- `write-file-create-flag` MUST
- `write-file-overwrite-flag` MUST
- `write-file-onto-directory` MUST
- `write-file-existence-at-the-link` MUST
- `write-file-not-atomic` MUST
- `create-directory-with-parents` MUST

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
