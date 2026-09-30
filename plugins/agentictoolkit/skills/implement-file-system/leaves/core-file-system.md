<!-- leaf: implement-file-system/core-file-system · source: file-system-core-file-system.md -->

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
