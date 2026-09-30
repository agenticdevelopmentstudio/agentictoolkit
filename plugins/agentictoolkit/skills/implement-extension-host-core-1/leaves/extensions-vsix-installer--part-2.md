<!-- leaf: implement-extension-host-core-1/extensions-vsix-installer--part-2 · source: extension-host-core-extensions-vsix-installer.md -->

# VSIXInstaller — continued (part 2)

**Rules** (cite as `implement-extension-host-core-1/extensions-vsix-installer--part-2#<slug>`):

- `injected-install-directory` MUST
- `default-host-version` MUST
- `injected-file-manager` MUST
- `sendable-value-type` MUST
- `registry-install-order` MUST
- `registry-installability-gate` MUST
- `registry-requires-universal-build` MUST
- `signature-pair-completeness` MUST
- `artifact-fetched-only-if-named` MUST
- `blocking-verification-hop` MUST
- `local-install-entry-point` MUST
- `scratch-directory-lifecycle` MUST
- `archive-expansion` MUST
- `payload-directory-required` MUST
- `manifest-read-and-localized` MUST
- `manifest-unreadable` MUST
- `manifest-malformed` MUST
- `identity-claim-checked` MUST
- `engine-range-checked` MUST
- `identity-fields-validated` MUST
- `directory-naming-convention` MUST
- `destination-containment-double-checked` MUST
- `install-directory-created` MUST
- `recovery-runs-before-scan` MUST
- `reinstall-idempotent` MUST
- `supersede-by-manifest-identity` MUST
- `supersede-non-fatal-removal` MUST
- `move-into-place-atomicity` MUST
- `move-into-place-rollback` MUST
- `aside-cleanup-on-success` MUST

## Behavioral Requirements

- **injected-install-directory**: `VSIXInstaller` MUST store `installDirectory`
  as an injected `URL` rather than deriving it internally, because the tier
  this type lives in cannot import `AppStorageLocation`, and because a test
  that installs into a real user's extensions directory would not be a test.
- **default-host-version**: `init`'s `hostVersion` parameter MUST default to
  `ExtensionRegistry.declaredVSCodeVersion`, which equals `SemanticVersion(major:
  1, minor: 138, patch: 0)` (66–68; `ExtensionRegistry.swift`).
- **injected-file-manager**: `init`'s `fileManager` parameter MUST be a
  `@Sendable () -> FileManager` closure defaulting to `{ .default }`, never a
  stored `FileManager` instance, because `FileManager` is not `Sendable` and
  this type is; every file operation MUST read the file manager through this
  closure.
- **sendable-value-type**: `VSIXInstaller` MUST be declared as a `Sendable`
  `struct`, usable concurrently from any thread or actor without additional
  synchronization for its own construction and property access, because its
  only stored properties are an immutable `URL`, an immutable
  `SemanticVersion`, and an immutable `@Sendable` closure.
- **registry-install-order**: `install(_:using:)` MUST decide installability
  from the record's metadata, then decide verification-artifact completeness
  from the record's metadata, before downloading anything; only after both
  checks pass MUST it download the archive and whichever verification
  artifacts the record named.
- **registry-installability-gate**: `install(_:using:)` MUST throw
  `VSIXInstallError.registryVersionUnusable(installability)` when
  `detail.installability(forHostVersion: hostVersion)` is not `.installable`,
  without making any request.
- **registry-requires-universal-build**: `install(_:using:)` MUST throw
  `VSIXInstallError.registryVersionUnusable(.noUniversalBuild)` when
  `detail.universalDownloadURL` is `nil`, without making any request.
- **signature-pair-completeness**: `install(_:using:)` MUST throw
  `VSIXInstallError.verificationIncomplete(published:missing:)`, before
  downloading the archive, when the record names exactly one of
  `signatureURL`/`publicKeyURL` and not the other — `verificationIncomplete(
  published: "signature", missing: "publicKey")` for a signature with no key,
  `verificationIncomplete(published: "publicKey", missing: "signature")` for a
  key with no signature.
- **artifact-fetched-only-if-named**: `install(_:using:)` MUST fetch
  `sha256URL`, and MUST fetch both `signatureURL` and `publicKeyURL` together,
  only when the record names each one; an artifact the record names but
  `client` cannot serve MUST propagate as `client`'s own thrown error, carrying
  the URL that failed.
- **blocking-verification-hop**: `install(_:using:)` MUST run archive
  verification (`VSIXArchive.verify`) and the local install
  (`install(archive:verification:expectedIdentifier:source:)`) inside
  `BlockingWork.run`, on a GCD global queue, rather than directly on the
  calling `async` context or inside `Task.detached` — because both steps are
  synchronous and blocking (a SHA-256 over up to 512 MB, then a write and a
  `ditto` invocation that can hold a thread for up to 124 seconds), and a
  detached task still occupies a cooperative-pool thread for the whole of that
  (`BlockingWork.swift`).
- **local-install-entry-point**: `install(archive:verification:
  expectedIdentifier:source:)` MUST be usable both as the tail of the registry
  flow above and as the sole entry point for archive bytes with no registry
  provenance (a user-supplied `.vsix`), with `expectedIdentifier` defaulting to
  `nil` for the latter case.
- **scratch-directory-lifecycle**: `install(archive:...)` MUST create a
  uniquely named scratch directory under `fileManager.temporaryDirectory`
  (`vsix-install-<UUID>`), and MUST remove it via `defer` on every exit path,
  successful or not.
- **archive-expansion**: `install(archive:...)` MUST write `archive` to
  `extension.vsix` inside the scratch directory and expand it with
  `VSIXArchive.expand` into an `expanded` subdirectory before reading anything
  from it.
- **payload-directory-required**: `install(archive:...)` MUST throw
  `VSIXInstallError.noPayloadDirectory` when `VSIXArchive.payloadDirectory(in:
  expanded)` does not exist — a zip that is not a `.vsix`.
- **manifest-read-and-localized**: `readManifest(in:)` MUST read
  `<payload>/package.json`, run its bytes through
  `ExtensionManifestLocalization.localize(_:forManifestIn:)` to resolve
  `%key%` placeholders against the payload's own nls tables, then through
  `JSONCPreprocessor.jsonData(from:)`, before decoding it as `ExtensionManifest`
  with a plain `JSONDecoder`.
- **manifest-unreadable**: `readManifest(in:)` MUST throw
  `VSIXInstallError.manifestUnreadable` when `package.json` cannot be read as
  `Data`.
- **manifest-malformed**: `readManifest(in:)` MUST throw
  `VSIXInstallError.manifestMalformed(String)`, carrying the decoder's
  `localizedDescription`, when the (localized, preprocessed) bytes do not
  decode as `ExtensionManifest`.
- **identity-claim-checked**: `install(archive:...)` MUST throw
  `VSIXInstallError.identityMismatch(claimed:found:)` when `expectedIdentifier`
  is non-`nil` and differs from the decoded `manifest.identifier`, before any
  further check runs — a registry claim the archive's own manifest does not
  bear out.
- **engine-range-checked**: `install(archive:...)` MUST throw
  `VSIXInstallError.engineRangeUnreadable(manifest.engines.vscode)` when
  `VSCodeEngineRange(manifest.engines.vscode)` fails to parse, and MUST throw
  `VSIXInstallError.engineIncompatible(manifest.engines.vscode, host:
  hostVersion.description)` when the parsed range does not accept
  `hostVersion` — both before the destination directory is computed or created.
- **identity-fields-validated**: `install(archive:...)` MUST call
  `requireSafeComponent` on both `manifest.identifier` and `manifest.version`,
  throwing `VSIXInstallError.unsafeIdentity(field:value:)` when either fails
  `ExtensionIdentityComponent.isSafe`, before either value becomes a directory
  name component, on every install path — `expectedIdentifier` above guards
  only one field on only the registry path, and `version` is compared with
  nothing else on any path (343–347;
  `ExtensionIdentityComponent.swift`).
- **directory-naming-convention**: `VSIXInstaller.directoryName(identifier:
  version:)` MUST return `"\(identifier)-\(version)"` — the layout the
  Marketplace installer writes — as pure string interpolation with no escaping
  and no validation of its own; the constraint that makes the result safe
  lives entirely in the caller's prior call to `requireSafeComponent`, not in
  this function.
- **destination-containment-double-checked**: `install(archive:...)` MUST
  independently verify, after building `destination`, that
  `ExtensionResourcePath.canonicalChild(directoryName, of: installDirectory)`
  is contained in `ExtensionResourcePath.canonicalDirectory(installDirectory)`,
  throwing `VSIXInstallError.unsafeIdentity(field: "identifier", value:
  destination.lastPathComponent)` when it is not — a check over the actual
  resolved path, distinct in kind from the string-level
  `identity-fields-validated` check above it, because a future change to
  `directoryName` that joined its parts differently would slip past the first
  and be caught here.
- **install-directory-created**: `install(archive:...)` MUST create
  `installDirectory`, with intermediate directories, before scanning it or
  writing into it — a first install into a fresh home MUST succeed, not be
  treated as an edge case (test `createsTheInstallDirectory`).
- **recovery-runs-before-scan**: `install(archive:...)` MUST call
  `recoverInterruptedInstalls()` before computing superseded directories or
  moving anything into place, so an aside a previous crash left behind is
  visible to the supersede sweep rather than invisible and unreclaimed.
- **reinstall-idempotent**: `install(archive:...)` MUST succeed, not throw a
  conflict, when the archive being installed is the same identifier and
  version already present at `destination` — the existing directory MUST be
  replaced rather than left alone, because its bytes are unproved and it may
  be a half-written tree an earlier attempt died inside, while the incoming
  bytes have already passed verification (test
  `reinstallIsIdempotent`).
- **supersede-by-manifest-identity**: `otherInstallDirectories(claiming:
  besides:)` MUST list every directory in `installDirectory` other than
  `destination`, skipping hidden entries, and MUST match a candidate by
  decoding its own `package.json` and comparing `manifest.identifier` — never
  by matching the candidate's folder name against any naming convention — so a
  hand-installed extension or a dev checkout named however its author named
  it is still recognized as superseded (test
  `supersedesAHandNamedDirectory`).
- **supersede-non-fatal-removal**: `install(archive:...)` MUST still return a
  successful `VSIXInstallation` when a superseded directory cannot be removed,
  logging the failure rather than throwing, because the new version is already
  in place and loadable by that point and reporting the install as failed
  would be false (test
  `anUnremovableSupersededCopyStillInstalls`).
- **move-into-place-atomicity**: `moveIntoPlace(_:to:)` MUST move an existing
  `destination` aside before moving the new payload in, never delete it
  first, so that a failure of the second move can restore the first; when
  `destination` did not previously exist, a failed move MUST throw
  `VSIXInstallError.couldNotInstall(reason)` directly with no aside step at
  all.
- **move-into-place-rollback**: `moveIntoPlace(_:to:)` MUST attempt to move
  the aside back to `destination` when the payload move fails and a previous
  copy existed; on a successful rollback it MUST throw
  `VSIXInstallError.couldNotInstall(reason)` naming only the original failure;
  on a failed rollback it MUST log the rollback failure at `error` level and
  throw `VSIXInstallError.couldNotInstall` naming both the original failure
  and that the previous version could not be put back, together with the
  aside's last path component.
- **aside-cleanup-on-success**: `moveIntoPlace(_:to:)` MUST attempt to remove
  the aside with `try?` once the new payload is successfully in place,
  swallowing any removal failure rather than surfacing it as part of a
  successful install.
