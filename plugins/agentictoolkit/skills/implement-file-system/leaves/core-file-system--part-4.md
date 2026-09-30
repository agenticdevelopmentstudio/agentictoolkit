<!-- leaf: implement-file-system/core-file-system--part-4 · source: file-system-core-file-system.md -->

# FileSystemService — continued (part 4)

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

