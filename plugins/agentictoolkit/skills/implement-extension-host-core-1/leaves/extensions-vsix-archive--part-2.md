<!-- leaf: implement-extension-host-core-1/extensions-vsix-archive--part-2 · source: extension-host-core-extensions-vsix-archive.md -->

# VSIXArchive — continued (part 2)

**Rules** (cite as `implement-extension-host-core-1/extensions-vsix-archive--part-2#<slug>`):

- `payload-directory-name` MUST
- `payload-directory-path` MUST
- `sha256-hex-format` MUST
- `digest-always-hashed` MUST
- `digest-comparison-normalized` MUST
- `digest-mismatch` MUST
- `digest-match-result` MUST
- `digest-not-published-result` MUST
- `digest-checked-before-signature` MUST
- `signature-neither-published` MUST
- `signature-half-pair-refused` MUST
- `signature-verified-with-real-key` MUST
- `signature-invalid` MUST
- `signature-manifest-and-p7s-ignored` MUST
- `signature-archive-extraction` MUST
- `signature-scratch-cleanup` MUST
- `public-key-parsing` MUST
- `expand-destination-must-not-exist` MUST
- `expand-destination-created` MUST
- `expand-uses-ditto` MUST
- `expand-default-parameters` MUST
- `expand-byte-ceiling-watchdog` MUST
- `expand-timeout-cleanup` MUST
- `expand-abort-cleanup` MUST
- `expand-nonzero-status-cleanup` MUST
- `expand-launch-failure-cleanup` MUST
- `expand-cleanup-is-best-effort` MUST
- `expand-success-preserves-destination` MUST
- `expand-path-traversal-containment` MUST
- `expand-symlink-escape-failure` MUST
- `expanded-size-measurement` MUST
- `byte-ceiling-exceeds-artifact-cap` MUST
- `stateless-namespace` MUST
- `synchronous-blocking-execution` MUST

- **payload-directory-name**: `VSIXArchive.payloadDirectoryName` MUST equal
  `"extension"`.
- **payload-directory-path**: `payloadDirectory(in: expanded)` MUST return
  `expanded` with `payloadDirectoryName` appended as a directory path
  component.
- **sha256-hex-format**: `sha256Hex(of:)` MUST return the SHA-256 digest of
  its input as lowercase hexadecimal, MUST be deterministic for the same
  bytes, and MUST differ for different bytes (test
  `digestIsOfTheBytes`).
- **digest-always-hashed**: `verify` MUST compute `sha256Hex(of: archive)`
  and return it as `VSIXVerification.sha256` on every call, whether or not
  `expectedDigest` is supplied (doc comment on `sha256`).
- **digest-comparison-normalized**: When `expectedDigest` is non-`nil`,
  `verify` MUST trim it of leading and trailing whitespace and newline
  characters with `trimmingCharacters(in: .whitespacesAndNewlines)` and
  lowercase it before comparing to the computed hash (test
  `digestComparisonIsForgivingAboutFormatting`).
- **digest-mismatch**: `verify` MUST throw
  `VSIXVerificationError.digestMismatch(expected:actual:)`, carrying the
  normalized `expectedDigest` and the computed `sha256Hex`, when the two do
  not match, and MUST NOT evaluate the signature in that case (test `digestMismatchThrows`).
- **digest-match-result**: When the normalized `expectedDigest` equals the
  computed hash, `verify`'s returned `digest` field MUST be `.matched` (test `digestComparisonIsForgivingAboutFormatting`).
- **digest-not-published-result**: When `expectedDigest` is `nil`, `verify`'s
  returned `digest` field MUST be `.notPublished`, distinct from `.matched`,
  even though `sha256` is still filled in (doc comment;
  test `noDigestStillHashes`).
- **digest-checked-before-signature**: `verify` MUST evaluate the digest
  before evaluating the signature, so a digest mismatch is reported as
  `digestMismatch` even when a signature and key are also supplied and would
  otherwise verify (the digest check precedes the signature check; test
  `digestIsCheckedFirst`).
- **signature-neither-published**: When both `signature` and `publicKeyPEM`
  are `nil`, `verify` MUST succeed and return `signature: .notPublished`
  rather than throwing (test `noDigestStillHashes`).
- **signature-half-pair-refused**: When exactly one of `signature` or
  `publicKeyPEM` is non-`nil`, `verify` MUST throw
  `VSIXVerificationError.signatureIncomplete(missing:)` naming the missing
  half as `"publicKey"` or `"signature"` respectively, without attempting any
  cryptographic check (test `halfThePairIsRefused`).
- **signature-verified-with-real-key**: When both `signature` and
  `publicKeyPEM` are non-`nil`, `verify` MUST extract the raw signature bytes
  from the `signature` `.sigzip` and the Ed25519 public key from the
  `publicKeyPEM` PEM text, and MUST check the signature against `archive`
  with `Curve25519.Signing.PublicKey.isValidSignature(_:for:)`, returning
  `signature: .registryAttested` on success (test
  `signatureVerifies`).
- **signature-invalid**: `verify` MUST throw
  `VSIXVerificationError.signatureInvalid` when the extracted signature does
  not validate against `archive` under the extracted key — whether because
  the bytes being verified were substituted or the signature bytes were
  corrupted (tests `signatureOverOtherBytesIsRefused`,
  `corruptedSignatureIsRefused`).
- **signature-manifest-and-p7s-ignored**: `verify` MUST verify the signature
  against `archive`'s bytes directly, using only `.signature.sig` from the
  `.sigzip`; it MUST NOT read or verify `.signature.manifest` or
  `.signature.p7s`, the other two entries a `.sigzip` may carry (doc comment).
- **signature-archive-extraction**: `signatureBytes(fromSigZip:)` MUST write
  its `Data` argument to a scratch file, expand it with `expand`, and read
  exactly `ed25519SignatureLength` (64) bytes from
  `.signature.sig` inside the expanded tree, throwing
  `VSIXVerificationError.signatureArchiveUnreadable` with a diagnostic string
  when that file is absent or is not exactly 64 bytes, or when writing or
  expanding the scratch archive itself fails (test
  `emptySignatureArchive`).
- **signature-scratch-cleanup**: `signatureBytes(fromSigZip:)` MUST remove
  its scratch directory via `defer` on every exit path, whether extraction
  succeeded or threw.
- **public-key-parsing**: `ed25519Key(fromPEM:)` MUST strip PEM header/footer
  lines (lines starting `-----`) and newline characters, base64-decode the
  remainder, and require exactly `ed25519SPKILength` (44) decoded bytes,
  taking the last `ed25519KeyLength` (32) bytes as the raw Ed25519 key;
  anything that fails base64 decoding or is not exactly 44 bytes, or whose
  final 32 bytes `Curve25519.Signing.PublicKey` refuses, MUST throw
  `VSIXVerificationError.publicKeyUnreadable` (test
  `unreadablePublicKey`).
- **expand-destination-must-not-exist**: `expand` MUST throw
  `VSIXArchiveError.destinationExists(destination)` without creating any
  directory or launching any process when `destination` already exists
  (test `expandRefusesAnExistingDestination`).
- **expand-destination-created**: When `destination` does not already exist,
  `expand` MUST create it, with intermediate directories, before launching
  `ditto`.
- **expand-uses-ditto**: `expand` MUST run `/usr/bin/ditto -x -k` with
  `archive.path` and `destination.path` as its two positional arguments,
  through `CommandRunner.runToCompletion`, rather than a Swift zip library
  (doc comment).
- **expand-default-parameters**: `expand`'s `timeout`, `byteCeiling`, and
  `checkInterval` parameters MUST default to `VSIXArchive.expansionTimeout`
  (120 seconds), `VSIXArchive.expansionByteCeiling` (2,147,483,648 bytes),
  and `VSIXArchive.expansionCheckInterval` (0.5 seconds) respectively.
- **expand-byte-ceiling-watchdog**: `expand` MUST supply
  `CommandRunner.runToCompletion` a `Watchdog` polled every `checkInterval`
  whose `shouldAbort` closure calls `expandedSize(of: destination,
  stoppingAbove: byteCeiling)` and returns whether that result exceeds
  `byteCeiling`.
- **expand-timeout-cleanup**: When the run's `Outcome.timedOut` is `true`,
  `expand` MUST attempt to remove `destination` and MUST throw
  `VSIXArchiveError.expansionTimedOut(seconds: timeout)` (test `anExpansionThatOutlastsItsBudgetIsStopped`).
- **expand-abort-cleanup**: When the run's `Outcome.aborted` is `true`,
  `expand` MUST attempt to remove `destination` and MUST throw
  `VSIXArchiveError.expansionTooLarge(bytes: byteCeiling)` (test `anOversizeExpansionIsStopped`).
- **expand-nonzero-status-cleanup**: When neither timed out nor aborted but
  `Outcome.status` is non-zero, `expand` MUST attempt to remove `destination`
  and MUST throw `VSIXArchiveError.expansionFailed(status:message:)`, with
  `message` set to `Outcome.diagnostics` (`ditto`'s trimmed standard error)
  (test `aSymlinkWrittenThroughFailsTheExpansion`).
- **expand-launch-failure-cleanup**: When `CommandRunner.runToCompletion`
  itself throws — `ditto` could not be launched at all — `expand` MUST
  attempt to remove `destination` and MUST throw
  `VSIXArchiveError.expansionUnavailable(String(describing: error))`.
- **expand-cleanup-is-best-effort**: Every removal of `destination` on a
  failure path MUST use `try?` rather than propagate a secondary error, so a
  failure to delete the partially written tree is discarded silently and
  never masks or replaces the original thrown error.
- **expand-success-preserves-destination**: When `Outcome.status == 0` and
  the run neither timed out nor aborted, `expand` MUST leave the fully
  expanded tree in place at `destination` and MUST NOT remove it (tests
  `expandProducesThePayload`, `theHandBuiltArchiveIsValid`).
- **expand-path-traversal-containment**: `expand` MUST NOT allow an archive
  entry named with a relative traversal (for example `../escaped.txt`) or an
  absolute path (for example `/tmp/x`) to write outside `destination`; both
  forms MUST land inside `destination`, flattened or re-rooted, because
  `ditto -x -k` provides this containment and `expand` neither disables nor
  duplicates it (doc comment; tests
  `aRelativeTraversalIsFlattened`, `anAbsoluteNameIsReRooted`).
- **expand-symlink-escape-failure**: When an archive entry is a symlink
  pointing outside `destination`, followed by an entry written through that
  symlink, `expand` MUST fail the whole run with a non-zero
  `Outcome.status` — reported as `expansionFailed` — rather than complete
  with the write silently redirected outside `destination` (doc comment; test `aSymlinkWrittenThroughFailsTheExpansion`).
- **expanded-size-measurement**: `expandedSize(of:stoppingAbove:)` MUST sum
  `totalFileAllocatedSize` (falling back to `fileAllocatedSize`) rather than
  logical file size for every item under `directory`, using
  `.skipsPackageDescendants` so a directory bundle is walked as ordinary
  files rather than skipped as an opaque package, and MUST return as soon as
  the running total exceeds `ceiling` without continuing to walk the rest of
  the tree.
- **byte-ceiling-exceeds-artifact-cap**: `VSIXArchive.expansionByteCeiling`
  MUST be greater than `OpenVSXClient.defaultMaximumArtifactBytes`, so the
  decompressed-size ceiling this type enforces is never tighter than the
  compressed-size ceiling the archive was already downloaded under (test `theDefaultCeilingIsAboveTheDownloadCap`).
- **stateless-namespace**: `VSIXArchive` MUST be declared as a `public enum`
  with no cases, holding only `static let` constants and `static func`
  operations and no stored instance property of any kind — it can never be
  instantiated, so it carries no per-call or shared mutable state and
  requires no explicit `Sendable` conformance to be safe to call from any
  thread or actor (full source).
- **synchronous-blocking-execution**: `verify` and `expand` MUST both be
  synchronous, non-`async` functions with no suspension point; `verify`
  performs its SHA-256 and Ed25519 work, and `expand` waits on
  `CommandRunner.runToCompletion`'s `DispatchSemaphore` for up to `timeout`
  plus up to two `terminationGrace` periods, entirely on the calling thread
  (145–151; `CommandRunner.swift`).
