<!-- leaf: implement-extension-host-core-1/extensions-vsix-installer--part-3 · source: extension-host-core-extensions-vsix-installer.md -->

# VSIXInstaller — continued (part 3)

**Rules** (cite as `implement-extension-host-core-1/extensions-vsix-installer--part-3#<slug>`):

- `aside-naming` MUST
- `recovery-sweep-scope` MUST
- `recovery-non-aside-entries-untouched` MUST
- `recovery-failure-logged` MUST
- `recovery-idempotent` MUST
- `installation-record-shape` MUST
- `runnable-here-computed` MUST
- `install-source-shape` MUST
- `directory-name-not-independently-safe` MUST
- `request-safe-component-error` MUST
- `logging-conformance` MUST
- `case-folded-manifest-identifier` MUST

- **aside-naming**: the aside a replaced directory is moved to MUST be named
  `.<destination.lastPathComponent>.replacing-<UUID>` — a leading dot so that
  `otherInstallDirectories` and `ExtensionRegistry.scan`, both of which pass
  `.skipsHiddenFiles`, do not see the second copy of the identifier that
  exists for the moment between the two renames.
- **recovery-sweep-scope**: `recoverInterruptedInstalls()` MUST list
  `installDirectory`'s contents with no hidden-file filtering (the opposite of
  every other listing in this file), and for every entry whose name
  `Self.replacedName(ofAside:)` recognizes, MUST either remove the aside (when
  its replaced destination already exists) or move the aside back to that
  destination (when it does not).
- **recovery-non-aside-entries-untouched**: `Self.replacedName(ofAside:)` MUST
  return `nil`, leaving the entry alone, for any hidden name that does not
  carry both the leading-dot prefix and the `.replacing-<nonce>` marker with a
  non-empty replaced name — an ordinary dotfile such as `.DS_Store` MUST NOT be
  touched by a recovery sweep (test
  `anUnrelatedHiddenEntryIsLeftAlone`).
- **recovery-failure-logged**: `recoverInterruptedInstalls()` MUST log, at
  `error` level, a failure to remove or restore a recognized aside, and MUST
  leave that aside exactly where it is rather than deleting it — it may be the
  only surviving copy of the extension.
- **recovery-idempotent**: `recoverInterruptedInstalls()` MUST be safe to call
  when no install is in progress and MUST be safe to call repeatedly, because
  it acts only on entries matching the aside naming convention and a live
  `moveIntoPlace` holds its aside for both of its renames on one synchronous,
  actor-free call path.
- **installation-record-shape**: On success, `install(archive:...)` MUST
  return a `VSIXInstallation` carrying `identifier`, `version`, `displayName`,
  `directory` (the final `destination`), `verification`, `source`,
  `supersededDirectories` (every directory this call removed or failed to
  remove), and `runnableHere`, all taken from the decoded manifest and the
  call's own inputs.
- **runnable-here-computed**: `VSIXInstallation.runnableHere` MUST equal
  `manifest.browser != nil || manifest.main == nil` — `true` for a web
  extension with a `browser` entry point or for a declarative-only extension
  with no entry point at all, `false` only for an extension that declares
  `main` and no `browser`; a `false` value MUST NOT be treated as a failed
  install, since the extension's declarative contributions still work (574–584; test `runnableHereFollowsTheEntryPoint`).
- **install-source-shape**: `VSIXInstallation.Source` MUST be either
  `.registry(String, version: String)` (the `<namespace>/<name>` and version
  asked for) or `.localFile(URL)` (a `.vsix` the caller supplied), and
  `install(_:using:)` MUST always construct the former from `detail.namespace
  + "/" + detail.name` and `detail.version`.
- **directory-name-not-independently-safe**: `directoryName(identifier:
  version:)` and the historical doc comment on it MUST be understood as pure
  joining that guarantees nothing on its own — a prior version of this
  function's documentation claimed npm-level constraints on `name` and
  `publisher` that do not exist, since nothing in this path runs npm and
  `publisher` is not an npm field; the actual constraint is
  `identity-fields-validated` and `destination-containment-double-checked`
  above, in the caller.
- **request-safe-component-error**: `requireSafeComponent(_:field:)` MUST
  throw `VSIXInstallError.unsafeIdentity(field:value:)` naming the actual
  field and the actual (unsafe) value, rather than a generic failure, because
  the person reading the message is the one who needs to see what the archive
  claimed.
- **logging-conformance**: `VSIXInstaller` MUST conform to `Loggable`,
  declaring `public static nonisolated let logger = makeLogger()`, giving it
  category `"VSIXInstaller"` under whatever subsystem `Bundle.main.
  bundleIdentifier` resolves to (`"nil"` when there is none) (`Loggable.swift`).
- **case-folded-manifest-identifier**: `manifest.identifier`, which
  `directory-naming-convention` and every identity check above consume, MUST
  already be the case-folded `publisher.name` (or bare `name` with no
  publisher) that `ExtensionManifest.identifier` computes — `VSIXInstaller`
  itself performs no case-folding of its own
  (`ExtensionManifest.swift`).
- **concurrent-install-ordering**: NEEDS REVIEW: Not implemented in source. No lock or actor serializes concurrent calls to `install(archive:...)` (or the `install(_:using:)` path that calls it) sharing one `installDirectory` value; each call independently runs `recoverInterruptedInstalls`, the supersede scan, `moveIntoPlace`, and superseded-directory cleanup against the same directory tree, and the source defines no ordering, mutual exclusion, or detection of that overlap.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `installDirectory` | `URL` | none (required) | Where installs land and are scanned for superseded copies; injected rather than derived. |
| `hostVersion` | `SemanticVersion` | `ExtensionRegistry.declaredVSCodeVersion` (`1.138.0`) | The VS Code engine version an archive's `engines.vscode` range is checked against. |
| `fileManager` | `@Sendable () -> FileManager` | `{ .default }` | File-system seam; a test substitutes a `FileManager` subclass that refuses a named move or removal. |
| `detail` (`install(_:using:)` parameter) | `OpenVSXExtensionDetail` | none (required) | The registry record naming the version, its download URL, and its verification artifacts. |
| `client` (`install(_:using:)` parameter) | `OpenVSXClient` | none (required) | How the archive and verification artifacts are fetched from the registry. |
| `archive` (`install(archive:...)` parameter) | `Data` | none (required) | The `.vsix` bytes already in hand. |
| `verification` (`install(archive:...)` parameter) | `VSIXVerification` | none (required) | What the bytes were already proved to be, computed by `VSIXArchive.verify` before this call. |
| `expectedIdentifier` (`install(archive:...)` parameter) | `String?` | `nil` | The identity a registry source claimed for the archive; `nil` when there is no claim to check (a user-supplied file). |
| `source` (`install(archive:...)` parameter) | `VSIXInstallation.Source` | none (required) | Whether this installation's provenance is recorded as `.registry` or `.localFile`. |

## Privacy

- **Data collected**: `VSIXInstaller` collects nothing beyond what the caller
  already supplies as arguments — the archive bytes, the registry's metadata
  fields it is given (`detail`), and whatever `expectedIdentifier`/`source` the
  caller passes. It reads no field from the archive's manifest that it did
  not already need for the checks above (identifier, version, `engines.vscode`,
  `displayName`, `browser`, `main`).
- **Storage**: The extension's expanded payload is written, unencrypted, as
  ordinary files under `installDirectory` — a persistent, caller-chosen
  location, typically `~/Library/Application Support/<App>/Extensions` in the
  shipping app (doc comment). A superseded copy and, briefly, a
  crash-orphaned aside are also written there under a hidden name before being
  removed.
- **Transmission**: `VSIXInstaller` itself makes no network request; on the
  registry path, `install(_:using:)` calls into `OpenVSXClient` to fetch the
  archive and its verification artifacts, so whatever `OpenVSXClient`'s own
  Privacy section states about that transmission applies here as well.
- **Retention**: The installed directory persists until a later install
  supersedes it (`supersede-by-manifest-identity`) or a caller elsewhere in the
  app removes it; `VSIXInstaller` sets no expiry or retention policy of its
  own on anything it writes.

