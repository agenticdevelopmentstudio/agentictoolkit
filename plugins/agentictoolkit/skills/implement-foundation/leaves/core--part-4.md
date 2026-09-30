<!-- leaf: implement-foundation/core--part-4 · source: foundation-core.md -->

# Foundation Core — continued (part 4)

## Design Decisions

- **Decision**: `get(forKey:)` re-stores a secret recovered from a legacy
  access-group scope or a retired service, but never deletes the original
  copy.
  **Rationale**: `KeychainHelper.swift`'s own doc comment states this
  directly — another install may still be reading the old item, and "a
  secret is not something to destroy on a guess."
  **Approved**: pending

- **Decision**: `SemanticVersion` rejects any component greater than
  `Int32.max` rather than accepting arbitrarily large numeric strings.
  **Rationale**: the source's doc comment explains that a version
  component is arithmetic, not just a label — `VSCodeEngineRange` computes
  a caret ceiling as `major + 1`, a trapping `Int` operation, and the guard
  is placed here so every consumer inherits it rather than each caller
  re-deriving its own bound.
  **Approved**: pending

- **Decision**: `SemanticVersion` parses only `major.minor.patch`, with no
  prerelease or build-metadata precedence.
  **Rationale**: the source's doc comment states that nothing in this
  toolkit currently needs prerelease/build-metadata comparison, and "half
  a precedence table is worse than an honest nil."
  **Approved**: pending

- **Decision**: `TextFolding.folded(_:)` passes `locale: nil` to `String
  .folding(options:locale:)` rather than `Locale.current`.
  **Rationale**: the source's doc comment cites the Turkish dotless-i
  problem — a case fold under `Locale.current` can vary by the user's
  system locale, which is wrong for matching against identifiers or titles
  that are not themselves localized.
  **Approved**: pending

- **Decision**: `KeychainHelper` marks access-group items
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` rather than a
  synchronizable accessibility class.
  **Rationale**: the source's doc comment explains a daemon consuming a
  shared access-group item may run before the user's first unlock of a
  session, and `ThisDeviceOnly` avoids iCloud Keychain sync/migration for
  material that should stay pinned to one device.
  **Approved**: pending

- **Decision**: `CodableIgnored`'s `encode(to:)` is a true no-op — the key
  is omitted from output entirely, rather than being written as `null`.
  **Rationale**: the source's inline comments state this directly: the
  key must never appear in encoded output, and decoding intentionally
  discards whatever was present, so an ignored field's contract is
  "invisible," not "present but nulled."
  **Approved**: pending

- **Decision**: `Loggable.swift` retains a large `#if false` block of
  authoring notes and usage examples after its real declarations.
  **Rationale**: this is a documented fact about the file's actual
  contents, not a convention to imitate — the block never compiles and has
  zero runtime effect; it is preserved here for source fidelity rather than
  silently dropped or treated as executable guidance.
  **Approved**: pending
