<!-- leaf: implement-extension-host-core-1/extensions-vsix-archive--part-3 · source: extension-host-core-extensions-vsix-archive.md -->

# VSIXArchive — continued (part 3)

**Rules** (cite as `implement-extension-host-core-1/extensions-vsix-archive--part-3#<slug>`):

- `concurrent-calls-independent-when-destinations-differ` MUST
- `logging-conformance-declared-unused` MUST
- `error-cases-carry-diagnostic-data` MUST

- **concurrent-calls-independent-when-destinations-differ**: Concurrent calls
  to `verify`, or to `expand` with distinct `destination` values, MUST run
  independently with no shared state between them: `verify` reads only its
  arguments, and each `expand`/`signatureBytes` call creates its own process
  and, for `signatureBytes`, its own `UUID`-named scratch directory.
- **logging-conformance-declared-unused**: `VSIXArchive` MUST conform to
  `Loggable`, declaring `public static nonisolated let logger =
  makeLogger()` scoped by that protocol's default to category
  `"VSIXArchive"`, but no function in `VSIXArchive` calls `logger` — every
  failure surfaces to the caller as a thrown `VSIXVerificationError` or
  `VSIXArchiveError` case instead of a log line (`Loggable.swift`).
- **error-cases-carry-diagnostic-data**: Every `VSIXArchiveError` case except
  `destinationExists` MUST carry data identifying why the run was stopped —
  a message, a byte count, or a duration — rather than a bare case with no
  payload, so a report against a failed install names what happened.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `expectedDigest` (`verify` parameter) | `String?` | — (required parameter, no default) | The registry-published SHA-256 hex digest to compare the archive against; `nil` means the registry published none. |
| `signature` (`verify` parameter) | `Data?` | — (required parameter, no default) | The registry-published `.sigzip` bytes; `nil` means no signature was published. |
| `publicKeyPEM` (`verify` parameter) | `String?` | — (required parameter, no default) | The registry-published Ed25519 public key, PEM-encoded SPKI; `nil` means no key was published. |
| `timeout` (`expand` parameter) | `TimeInterval` | `VSIXArchive.expansionTimeout` (120 seconds) | How long `ditto` is given to finish before the run is terminated and reported as timed out. |
| `byteCeiling` (`expand` parameter) | `Int64` | `VSIXArchive.expansionByteCeiling` (2,147,483,648 bytes) | How much allocated disk space may land under `destination` before the run is aborted and reported as too large. |
| `checkInterval` (`expand` parameter) | `TimeInterval` | `VSIXArchive.expansionCheckInterval` (0.5 seconds) | How often `destination`'s size is measured against `byteCeiling` while `ditto` runs. |

## Privacy

- **Data collected**: `VSIXArchive` collects nothing of its own; it operates
  on whatever `archive` bytes, `expectedDigest`, `signature`, and
  `publicKeyPEM` the caller already holds, all of which originate from the
  registry response the caller fetched, not from a person using this device.
- **Storage**: `expand` writes the decompressed extension tree to the
  caller-supplied `destination`, which persists after the call returns by
  design — that is the point of expanding an archive. `signatureBytes`'s
  internal scratch directory, used only to expand a `.sigzip` far enough to
  read `.signature.sig`, is always removed via `defer` before the call
  returns (`signature-scratch-cleanup`).
- **Transmission**: None. `VSIXArchive` performs no network I/O — its only
  imports are `CryptoKit`, `Foundation`, and `OSLog`.
- **Retention**: `VSIXArchive` is a stateless namespace and retains nothing
  across calls (`stateless-namespace`); how long the expanded tree at
  `destination` is kept is decided entirely by the caller once `expand`
  returns.

## Platform Notes

- **SwiftUI**: Source:
  `packages/apple/AgenticToolkit/Core/Extensions/VSIXArchive.swift`, its
  process runner in `Core/Process/CommandRunner.swift`, and its `Loggable`
  conformance from `Core/Loggable.swift`. The type is plain `Foundation`,
  `CryptoKit`, and `OSLog` with no SwiftUI dependency; a SwiftUI-hosted
  install flow calls `verify` and `expand` from a `Task` on a dedicated
  blocking-work executor (as `VSIXInstaller` does), since both functions
  block the calling thread rather than suspending, and reflects the result
  or thrown error into its own `@State`/`@Observable` view state.
- **Compose**: On Kotlin/Android, port to an object exposing
  `fun verify(archive: ByteArray, expectedDigest: String?, signature:
  ByteArray?, publicKeyBytes: ByteArray?): VSIXVerification` and
  `fun expand(archive: File, destination: File, timeoutMs: Long, byteCeiling:
  Long, checkIntervalMs: Long)`. Compute the digest with
  `java.security.MessageDigest.getInstance("SHA-256")`; verify the Ed25519
  signature with a JCA provider that supports the `Ed25519` algorithm (or
  BouncyCastle if the platform's default provider does not) rather than
  hand-rolling curve math. There is no `ditto` equivalent, so extraction must
  use `java.util.zip.ZipInputStream` directly and re-implement the two
  containment rules by hand: reject or re-root an entry name containing `..`
  or an absolute path before resolving it against `destination`, and refuse
  to follow a symlink entry rather than trusting an OS unarchiver to do it.
  Run the unpacking loop on a background dispatcher with an explicit
  coroutine timeout (`withTimeout`) and a running-byte-count check against
  `byteCeiling`, since there is no OS-level watchdog process to poll.
- **React/Web**: There is no filesystem or code-signing equivalent to port
  directly in a browser context; a Node.js or Electron host is the
  realistic target. Compute the digest with Node's `crypto.createHash`
  `sha256`; verify the Ed25519 signature with `crypto.verify` given a `raw`
  or `spki`-encoded public key via `crypto.createPublicKey`. Expand the
  archive with a zip library (for example `yauzl` or `unzipper`) reading
  entries one at a time, explicitly rejecting or re-rooting any entry whose
  normalized path escapes `destination` and refusing symlink entries outright
  — Node's zip libraries do not provide `ditto`'s containment guarantees, so
  this logic has to be written rather than delegated. Bound the run with a
  timer that aborts the read stream past `timeout`, and a running
  allocated-byte count checked against `byteCeiling` on each entry.
- **AppKit / UIKit**: No divergence from the SwiftUI bullet above — the
  source is framework-agnostic `Foundation`/`CryptoKit` code plus one
  `Process` launch, callable identically from an AppKit-hosted (macOS) or
  UIKit-hosted (iOS) caller. `AgenticToolkitCore`, the framework target that
  builds this file, is configured `platform: macOS` in
  `packages/apple/AgenticToolkit/project.yml` today; `/usr/bin/ditto` itself
  is a macOS command-line tool with no iOS equivalent, so an iOS port of
  `expand` specifically (not `verify`) would need a pure-Swift or
  `libarchive`-based unzip that re-implements the same two containment
  checks `ditto` provides today, which is the one piece of this component
  that is not simply "the same code, another target."
- **WinUI 3**: Port to a static class exposing `VSIXVerification Verify(byte[]
  archive, string? expectedDigest, byte[]? signature, string? publicKeyPem)`
  and `void Expand(string archivePath, string destinationPath, TimeSpan
  timeout, long byteCeiling, TimeSpan checkInterval)`. Compute the digest
  with `System.Security.Cryptography.SHA256.HashData`, formatted lowercase
  hex with `Convert.ToHexString(...).ToLowerInvariant()`. Verify the Ed25519
  signature with a package that supports it directly — .NET's built-in
  `System.Security.Cryptography` has no Ed25519 API as of .NET 8, so this is
  the one primitive that needs an external library (for example
  `NSec.Cryptography` or a BouncyCastle wrapper), unlike the source's direct
  `Curve25519.Signing.PublicKey` from CryptoKit. There is no bundled
  Windows equivalent to `ditto`'s zip-slip and symlink containment, so
  extraction should go through `System.IO.Compression.ZipFile` entry-by-entry
  (never `ZipFile.ExtractToDirectory`, which does not defend against a
  traversing entry name) with each entry's resolved full path checked with
  `Path.GetFullPath` against `destinationPath` before it is written, and any
  entry whose `ZipArchiveEntry` represents a reparse point (symlink) refused
  outright. Run the extraction loop on a background `Task.Run`, enforce
  `timeout` with a `CancellationTokenSource`, and check the running byte
  count against `byteCeiling` inside the same loop rather than polling a
  separate process, since there is no child process to watch. No
  `ObservableCollection` or `INotifyPropertyChanged` belongs on this type
  itself, since it has no UI-observable state of its own — those apply only
  to whatever ViewModel wraps calls into it.

