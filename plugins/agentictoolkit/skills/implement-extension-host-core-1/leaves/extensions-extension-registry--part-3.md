<!-- leaf: implement-extension-host-core-1/extensions-extension-registry--part-3 · source: extension-host-core-extensions-extension-registry.md -->

# Extension Registry — continued (part 3)

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-registry--part-3#<slug>`):

- `set-enabled-migrates-persisted-casing` MUST
- `set-enabled-drives-contribution-points` MUST
- `set-enabled-unloaded-identifier-persists-only` MUST
- `set-enabled-notifies-only-on-change` MUST
- `uninstall-deletes-then-updates-memory` MUST
- `uninstall-unknown-identifier-is-a-no-op` MUST
- `uninstall-notifies-once` MUST
- `established-identifiers-nil-when-incomplete` MUST
- `established-identifiers-nil-on-unnameable-failure` MUST
- `established-identifiers-union` MUST
- `established-identifiers-initial-state` MUST
- `contribution-registrations-not-part-of-registry-state` MUST

- **set-enabled-migrates-persisted-casing**: When `setEnabled(_:for:)` does change state, it MUST remove every case-insensitive match of `identifier` from `UserSettings.disabledExtensionIdentifiers.value` and, if disabling, insert exactly the lower-cased form, so the persisted set converges toward one canonical casing per identifier over successive toggles.
- **set-enabled-drives-contribution-points**: When `setEnabled(_:for:)` changes an already-loaded extension's enabled state, enabling MUST call `applyContributions` for it (passing `.empty` if its manifest has no `contributes`), and disabling MUST call `withdraw(extensionIdentifier:)` on every registered point and then `removeContributionFailures(at:)` for its directory.
- **set-enabled-unloaded-identifier-persists-only**: `setEnabled(_:for:)` for an identifier not present in `extensions` MUST still update `UserSettings.disabledExtensionIdentifiers`, but MUST NOT call any `ContributionPoint` and MUST NOT fire the contributions-observer notification.
- **set-enabled-notifies-only-on-change**: `setEnabled(_:for:)` MUST call `notifyContributionsDidChange()` only after it has actually changed the enabled state of an extension that is currently loaded; the no-op case and the unloaded-identifier case MUST NOT notify.
- **uninstall-deletes-then-updates-memory**: `uninstall(_:)` MUST call `FileManager.default.removeItem(at:)` on the extension's directory before removing it from `extensions`, withdrawing its contributions from every registered point, clearing its `contributionPointFailed` entries, and removing it from `UserSettings.disabledExtensionIdentifiers`; if the delete throws, `uninstall(_:)` MUST propagate that error and MUST leave `extensions`, `failures`, every contribution point's state, and the disabled-identifiers set completely unchanged.
- **uninstall-unknown-identifier-is-a-no-op**: `uninstall(_:)` for an identifier not present (case-folded) in `extensions` MUST return without throwing, without touching the file system, and without any other side effect.
- **uninstall-notifies-once**: A successful `uninstall(_:)` MUST call `notifyContributionsDidChange()` exactly once, after every other state change it performs.
- **established-identifiers-nil-when-incomplete**: `establishedIdentifiers` MUST be `nil` whenever `scanReadEverything` is `false`, regardless of the contents of `extensions` or `failures`.
- **established-identifiers-nil-on-unnameable-failure**: `establishedIdentifiers` MUST be `nil` whenever any entry in `failures` has `identifier == nil`, even if `scanReadEverything` is `true`.
- **established-identifiers-union**: When neither condition above applies, `establishedIdentifiers` MUST return the union of every loaded extension's identifier and every failure's non-nil identifier, as a `Set<String>`.
- **established-identifiers-initial-state**: A newly constructed `ExtensionRegistry` on which `loadAll()`/`reload()` has never been called MUST report `establishedIdentifiers == nil`, because `scanReadEverything` starts `false`.
- **contribution-registrations-not-part-of-registry-state**: `ExtensionRegistry` itself MUST hold no `ContributionRegistrations` value; per-point bookkeeping of what was applied belongs to each `ContributionPoint` conformer (see the `extension-host-core-extensions-contribution-point` recipe), not to the registry.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `searchPaths` (`init(searchPaths:hostVersion:)`) | `[URL]` | none — required | Directories to scan for extension folders; caller-resolved, since `ExtensionRegistry` cannot import the tier that would derive them (see Design Decisions). |
| `hostVersion` (`init(searchPaths:hostVersion:)`) | `SemanticVersion` | none — required | The running host's own version, compared only by `ActivationEventMatcher` and callers outside this file; not the value the engine gate checks against. |
| `ExtensionRegistry.declaredVSCodeVersion` | `SemanticVersion` (`nonisolated static let`) | `1.138.0` | The VS Code API surface version every extension's `engines.vscode` is gated against during `loadAll()`/`reload()`. |
| `UserSettings.disabledExtensionIdentifiers` | `UserSetting<Set<String>>` (`"extensions.disabledIdentifiers"`) | `[]` | Persisted, case-insensitively-compared set of identifiers the user has switched off; absence from this set means enabled. |
| Registered `ContributionPoint`s (`register(_:)`) | `[any ContributionPoint]` | `[]` | Points that receive `apply`/`withdraw` calls for each enabled extension's `contributes.*` blocks; caller-supplied, order-preserving. |
| Contributions observers (`addContributionsObserver(_:)`) | `[(token: UUID, handler: () -> Void)]` | `[]` | Handlers called once after every load, reload, enable/disable, or uninstall that changed live contribution state. |

## Localization

`ExtensionRegistry.swift` defines no user-facing string of its own; every string it carries into its `ExtensionLoadError` cases and log lines is either a manifest-derived identifier/path or a developer-facing diagnostic. It does, however, drive manifest localization for the extension's own declared strings: every `package.json` decode is routed through `ExtensionManifestLocalization.localize(_:forManifestIn:)` (manifest-localization-applied-before-decode) before the JSONC preprocessor and the `ExtensionManifest` decode, so an extension's own `%configuration.title%`-style placeholder resolves against its `package.nls.json` before any downstream caller ever sees the manifest's strings.

## Privacy

- **Data collected**: `ExtensionRegistry` reads only extension manifest metadata from disk — identifiers, versions, engine ranges, and `contributes.*` declarations — and the user's own set of disabled extension identifiers. It reads no credential, token, or other secret value; a manifest's own contents are third-party-authored text, not user-entered secrets.
- **Storage**: The only persisted state this file writes is `UserSettings.disabledExtensionIdentifiers` (a set of extension identifier strings) via `setEnabled`/`uninstall`. `extensions`, `failures`, and `contributionPoints` are in-memory only and are rebuilt from disk by every `loadAll()`/`reload()`.
- **Transmission**: Not applicable — this file performs no networking.
- **Retention**: `extensions` and `failures` live only as long as the `ExtensionRegistry` instance and are wholly replaced by each `apply(_:)`; `UserSettings.disabledExtensionIdentifiers` persists across launches until `uninstall(_:)` clears an identifier's tombstone or a user explicitly re-enables it.

