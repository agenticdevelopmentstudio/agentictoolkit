<!-- leaf: implement-extension-host-core-1/extensions-extension-manifest-localization--edge-cases · source: extension-host-core-extensions-extension-manifest-localization.md -->

# ExtensionManifestLocalization

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-manifest-localization--edge-cases#<slug>`):

- `null-empty-input` MUST — json as empty Data MUST be returned unchanged — JSONCPreprocessor.jsonObject(from:) throws for empty bytes, which the …
- `boundary-values` MUST — A string of exactly "%%" (count == 2) MUST NOT be treated as a placeholder — the string.count > 2 guard rejects it. A …
- `concurrent-access` MUST — ExtensionManifestLocalization is a caseless enum with no stored state; every function is a static function of its …
- `error-states` MUST — A directory that does not exist, cannot be listed, or holds a package.nls*.json file that cannot be read or does not …

## Edge Cases

- **Null/empty input**: `json` as empty `Data` MUST be returned unchanged —
  `JSONCPreprocessor.jsonObject(from:)` throws for empty bytes, which the
  `try?` in `localize` catches. A `package.nls.json` whose content
  is the valid, empty object `{}` MUST leave the merged table empty and
  MUST NOT change `localize`'s no-table behavior. MUST.
- **Boundary values**: A string of exactly `"%%"` (`count == 2`) MUST NOT be
  treated as a placeholder — the `string.count > 2` guard rejects it. A string of exactly `"%x%"` (`count == 3`, the shortest possible
  placeholder) MUST be treated as one. A key containing any `%` character,
  at any position, MUST be rejected before lookup. MUST.
- **Concurrent access**: `ExtensionManifestLocalization` is a caseless enum
  with no stored state; every function is a `static` function of its
  arguments and touches only local values and freshly-read files, never a
  shared cache. `ExtensionRegistry.read` and `VSIXInstaller.readManifest`
  both call `localize` from `nonisolated` contexts (`ExtensionRegistry.swift`'s `private nonisolated static func read`), and concurrent,
  independent calls with independent `directory` arguments MUST NOT require
  external synchronization. Two concurrent calls that both name the *same*
  `directory` while one of its table files is being modified on disk are not
  independent, and the file system's own read consistency, not this file,
  decides what either call sees. MUST.
- **Error states**: A `directory` that does not exist, cannot be listed, or
  holds a `package.nls*.json` file that cannot be read or does not parse as
  JSON/JSONC MUST NOT fail `localize` — every such failure resolves to that
  file (or the whole table) contributing no entries, per
  **unreadable-directory-yields-no-tables**,
  **unreadable-table-file-contributes-nothing**, and
  **malformed-table-contributes-nothing**. None of these failures is
  surfaced anywhere — not as a thrown error, a return value, or a log line
  (see Logging) — which is a deliberate design choice, not an omission (see
  Design Decisions). MUST.
- **Offline/disconnected state**: Not applicable — this file performs no
  network access of any kind; `localize`, `table`, `entries`, and
  `fileNames` operate only on `FileManager`/`Data(contentsOf:)` calls
  against the local file system named by `directory`.
- **Cancellation and timeouts**: Not applicable — `localize` is a
  synchronous, non-`async` function with no `Task`, no cooperative
  cancellation check, and no timeout of any kind anywhere in this file; it
  always runs to completion once called.
