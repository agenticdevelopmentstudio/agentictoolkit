<!-- leaf: implement-extension-host-core-1/extensions-vsix-installer--part-4 · source: extension-host-core-extensions-vsix-installer.md -->

# VSIXInstaller — continued (part 4)

## Platform Notes

- **SwiftUI**: Source:
  `packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift`, its
  verification and expansion in `Core/Extensions/VSIXArchive.swift`, its
  identity and containment guards in `Core/Extensions/
  ExtensionIdentityComponent.swift` and `Core/Extensions/
  ExtensionResourcePath.swift`, its manifest decode in `Core/Extensions/
  ExtensionManifest.swift`, and its blocking-work hop in `Core/Concurrency/
  BlockingWork.swift`. The type is plain `Foundation`/`OSLog` with no SwiftUI
  dependency; a SwiftUI-hosted extensions panel calls either `install`
  overload with `async`/`await` from a `Task` and renders the returned
  `VSIXInstallation` or caught `VSIXInstallError` into its own `@State`/
  `@Observable` view state — `VSIXInstaller` itself holds none.
- **Compose**: On Kotlin/Android, port to a class exposing
  `suspend fun install(detail: OpenVsxExtensionDetail, using: OpenVsxClient):
  VsixInstallation` and a synchronous
  `fun install(archive: ByteArray, verification: VsixVerification,
  expectedIdentifier: String?, source: VsixInstallation.Source):
  VsixInstallation`. Run the synchronous half — hashing, unzip, and the
  move-and-rollback sequence — with `withContext(Dispatchers.IO)` rather than
  the default coroutine dispatcher, mirroring why `BlockingWork` exists: IO
  threads are the pool that is allowed to block. Reuse the ported
  `ExtensionIdentityComponent.isSafe` and a `File`-based containment check
  (`canonicalFile` compared by path-segment prefix, not string prefix) before
  either becomes a path. `File.renameTo` is the closest analogue to `rename(2)`
  for the atomic swap, but is documented as platform- and filesystem-dependent
  on Android, so a port should verify it behaves atomically within the target
  storage volume or fall back to copy-then-delete-old with the same aside
  convention if not.
- **React/Web**: There is no local file system to install into in a browser
  context, so a literal port has no destination; where this runs inside an
  Electron-style host with Node's `fs` module available, port to an `async
  function install(archiveBytes: Uint8Array, verification: VsixVerification,
  expectedIdentifier: string | null, source: VsixInstallationSource):
  Promise<VsixInstallation>`. Use `fs.promises.rename` for the atomic swap
  (POSIX `rename(2)` semantics on the same volume), a zip library with
  path-traversal and symlink protection equivalent to `ditto`'s (many
  JavaScript zip libraries do not refuse a traversing or symlink-escaping
  entry by default and would need an explicit per-entry path check), and
  reuse the ported `isSafe` and a `path`-segment containment check before any
  extracted or joined path is used.
- **AppKit / UIKit**: No divergence from the SwiftUI bullet above — the
  source is framework-agnostic `Foundation` code, callable identically from an
  AppKit-hosted (macOS) or UIKit-hosted (iOS) caller. `AgenticToolkitCore`, the
  framework target that builds this file, is configured `platform: macOS` in
  `packages/apple/AgenticToolkit/project.yml` today, so an iOS caller would
  first need the type made available to an iOS target; `VSIXInstaller` itself
  needs no AppKit/UIKit-specific change to run there.
- **WinUI 3**: Port to a class exposing `async Task<VsixInstallation>
  InstallAsync(OpenVsxExtensionDetail detail, OpenVsxClient client)` and a
  synchronous `VsixInstallation Install(byte[] archive, VsixVerification
  verification, string? expectedIdentifier, VsixInstallationSource source)`.
  Offload the synchronous half onto `Task.Run`, which is a reasonable
  counterpart to `BlockingWork` here even though .NET's thread pool grows to
  accommodate blocking work rather than being a fixed cooperative pool — the
  concern is milder, not absent, since a large enough number of concurrently
  blocking `Task.Run` calls still exhausts the pool before it can grow. Hash
  with `System.Security.Cryptography.SHA256`; .NET has no built-in Ed25519
  verifier as of this writing, so the signature check ported from
  `VSIXArchive.verify` needs a third-party library (for example `NSec.
  Cryptography` or a `libsodium` binding) rather than a framework type.
  Extract the archive with `System.IO.Compression.ZipFile.ExtractToDirectory`
  or an equivalent, but note it does **not** refuse a `../`-escaping or
  symlink-escaping zip entry the way `ditto -x -k` does — a port needs an
  explicit per-entry destination-containment check before extraction, not
  merely a check on the final tree. Decode the manifest with `System.Text.
  Json`'s `JsonSerializer.Deserialize` against a matching record type. Port
  `ExtensionIdentityComponent.IsSafe` and call it on both the identifier and
  the version before either reaches `Path.Combine` — which, like
  `appendingPathComponent`, performs no escaping of its own. Use
  `System.IO.Directory.Move` for the aside-then-swap sequence; it is a rename
  within one NTFS volume and shares `rename(2)`'s all-or-nothing character
  there, but throws `IOException` across volumes rather than completing, so a
  port should confirm both directories live under one volume the way this
  source implicitly relies on `installDirectory` and its parent doing. No
  `ObservableCollection` or `INotifyPropertyChanged` belongs on this type
  itself, since it has no UI-observable state of its own — those apply only to
  whatever ViewModel wraps calls into it.

## Design Decisions

**Decision**: Move an existing `destination` directory aside before moving the
new payload in, rather than deleting the old copy first.
**Rationale**: A failure during the second move can then restore the first;
deleting the old copy first would leave the user with neither version if the
second move then failed — the one outcome that would make an update button
unsafe to press (doc comment; `moveIntoPlace`).
**Approved**: pending

**Decision**: Check destination containment twice — once as a predicate over
the identifier and version strings (`ExtensionIdentityComponent.isSafe`), once
as a fact about the actual resolved destination path
(`ExtensionResourcePath.canonicalChild`/`url(isContainedIn:)`).
**Rationale**: The two checks fail for different reasons. A future change to
`directoryName(identifier:version:)` that joined its parts differently would
slip straight past the string-level predicate and still be caught by the
path-level check, which is closer to what `moveIntoPlace`'s underlying
`rename(2)` actually resolves.
**Approved**: pending

**Decision**: Canonicalize the install directory's *parent*, which exists,
and append the new component to that — rather than canonicalizing the full,
not-yet-existing destination path.
**Rationale**: `resolvingSymlinksInPath()` drops a leading `/private` only
when what remains still names something real. The version of this guard that
canonicalized the whole destination refused every ordinary install into an
extensions folder reached through `/private` (a macOS temporary directory, or
a home on another volume) with `unsafeIdentity`, naming a perfectly ordinary
`<publisher>.<name>-<version>` (`ExtensionResourcePath.swift`; test `aPrivateRootedInstallDirectoryStillInstalls`).
**Approved**: pending

**Decision**: Match superseded directories by decoding each candidate's own
`package.json` and comparing its `identifier`, never by matching the
candidate's folder name against a naming convention.
**Rationale**: A hand-installed extension or a dev checkout is named however
its author named it, and those are exactly the copies whose survival would
shadow the extension just installed if the sweep trusted names instead of
content (doc comment; test `supersedesAHandNamedDirectory`).
**Approved**: pending

**Decision**: Report the failure of a rollback (moving the aside back after
the new payload's move also failed) as a distinct outcome from the original
move failure, rather than the same `try?`-discarded error both used to share.
**Rationale**: The thrown error used to carry only the original failure's
reason, so the one outcome this whole aside-and-swap dance exists to
prevent — the user left with no version of the extension at all — was
reported in exactly the same words as the safe outcome where the previous
version simply went back. The aside's own name is included because a person
can move it back by hand and nothing else on disk says where it went.
**Approved**: pending

**Decision**: Let a superseded copy that cannot be removed, and a
crash-recovery aside that cannot be restored or discarded, fail quietly (a
logged warning or error) rather than fail the calling operation.
**Rationale**: In both cases the alternative on-disk state is already
correct, or already the best available outcome, by the time the failure
happens — the new version is installed and loadable, or the aside is still
the only surviving copy and deleting it would turn a recoverable state into
an unrecoverable one. Throwing would report an install that succeeded (or a
recovery that did the safe thing) as having failed.
**Approved**: pending
