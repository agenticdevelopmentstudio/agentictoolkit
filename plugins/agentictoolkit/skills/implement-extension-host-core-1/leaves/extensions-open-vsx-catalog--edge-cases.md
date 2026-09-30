<!-- leaf: implement-extension-host-core-1/extensions-open-vsx-catalog--edge-cases · source: extension-host-core-extensions-open-vsx-catalog.md -->

# OpenVSXCatalog

**Rules** (cite as `implement-extension-host-core-1/extensions-open-vsx-catalog--edge-cases#<slug>`):

- `null-empty-input` MUST — {} decoded as OpenVSXSearchEntry or as OpenVSXExtensionDetail MUST throw, because namespace, name, and version are …
- `boundary-values` MUST — engines.vscode absent and engines.vscode present as the empty string MUST both be treated as "not gated," yielding …
- `concurrent-access` MUST — OpenVSXSearchEntry, OpenVSXSearchPage, OpenVSXExtensionDetail, and OpenVSXInstallability are Sendable, side-effect-free …
- `error-states` MUST — A malformed required field (namespace, name, or version, on either OpenVSXSearchEntry or OpenVSXExtensionDetail) MUST …

## Edge Cases

- **Null/empty input**: `{}` decoded as `OpenVSXSearchEntry` or as
  `OpenVSXExtensionDetail` MUST throw, because `namespace`, `name`, and
  `version` are non-optional on both types. A `files`
  key present but empty (`{}`) MUST decode to `[:]`, distinct from an absent
  `files` key, which MUST decode to `nil` (open-vsx-catalog-003).
- **Boundary values**: `engines.vscode` absent and `engines.vscode` present
  as the empty string MUST both be treated as "not gated," yielding
  `.installable` when nothing else refuses (open-vsx-catalog-013); a
  `VSCodeEngineRange` string with a leading `>= ` (a space inside the
  operator, rather than immediately before a digit) MUST instead be treated
  as unreadable, because `VSCodeEngineRange`'s own grammar rejects interior
  whitespace (open-vsx-catalog-012). `URL(string: "")` MUST resolve to `nil`
  under Foundation's own `URL` initializer, so a `downloads["universal"]`
  entry of the empty string MUST behave identically to that key being
  absent — `.noUniversalBuild`.
- **Concurrent access**: `OpenVSXSearchEntry`, `OpenVSXSearchPage`,
  `OpenVSXExtensionDetail`, and `OpenVSXInstallability` are `Sendable`,
  side-effect-free value types touching no shared mutable state; concurrent,
  independent decode or `installability(forHostVersion:)` calls MUST NOT
  require external synchronization (**catalog-types-are-sendable-value-types**).
- **Error states**: A malformed required field (`namespace`, `name`, or
  `version`, on either `OpenVSXSearchEntry` or `OpenVSXExtensionDetail`)
  MUST sink the decode of the entry and, for a page, the whole page
  (open-vsx-catalog-008) — a visible failure. A malformed *optional* field,
  or a URL-shaped string that fails to parse, MUST instead resolve silently
  to `nil` with no diagnostic value recorded anywhere in this file — there
  is no equivalent, in `OpenVSXCatalog.swift`, of the sibling
  `ExtensionManifest.DecodingFailure` record; the caller sees only an
  absence, indistinguishable from the key never having been sent (see
  Design Decisions).
- **Offline/disconnected state**: Not applicable — this file performs no
  network or file I/O of its own; every type here operates purely on the
  `Decoder`, `Data`, or already-decoded fields its caller already obtained,
  with no `URLSession`, `FileManager`, or process call anywhere in
  `OpenVSXCatalog.swift`.
