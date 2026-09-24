---
id: dbe4b3b6-ac5b-4d45-ba2a-84aad1a8582e
title: VSIXArchive
domain: agentictoolkit://recipes/extension-host-core-extensions-vsix-archive
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Proves a downloaded .vsix's bytes against a registry-published digest
  and signature, then expands it to disk through a timed, size-bounded ditto run."
platforms:
- swift
- macos
tags:
- extension-host
- vsix
- containment
- code-signing
depends-on: []
related:
- agentictoolkit://recipes/extension-host-core-extensions-open-vsx-client
references:
- packages/apple/AgenticToolkit/Core/Extensions/VSIXArchive.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Process/CommandRunner.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# VSIXArchive

## Overview

`VSIXArchive` is a stateless namespace `enum` with two public operations on a
downloaded `.vsix` file: `verify`, which checks the raw archive bytes against
whatever digest and Ed25519 signature the registry published for them, and
`expand`, which unpacks the archive onto disk through the platform's own
`ditto` unarchiver under a timeout and a decompressed-size ceiling (source:
doc comment on `VSIXArchive`). A `.vsix` is a zip whose extension
tree lives under an `extension/` subdirectory alongside packaging metadata
this host does not read; `payloadDirectory(in:)` is the one place that
subdirectory name is spelled out.

Both operations are read-only with respect to the network: nothing here
downloads anything. The one caller in this codebase,
`packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift`, fetches
the archive bytes and the optional digest/signature/key text over HTTP
itself, then calls `VSIXArchive.verify` followed by `VSIXArchive.expand`
synchronously, inside a dedicated blocking-work context, because neither
function suspends and both can hold a thread for the length of a 512 MB
download's worth of hashing or a `ditto` run (`VSIXInstaller.swift`).

`verify`'s doc comment states plainly what its two checks do and do not
establish: the digest and signature are both checked against values the
*registry* published in the same response that named the archive, never
against an out-of-band publisher key, so a registry serving altered bytes
under a key of its own passes every check here. That is why a fully verified
result is named `.registryAttested` rather than `.verified`.

## Behavioral Requirements

All line references below are to
`packages/apple/AgenticToolkit/Core/Extensions/VSIXArchive.swift` unless
another file is named.

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

## Appearance

Not applicable — this is a file-verification and archive-extraction utility,
not a visual component.

## States

Not applicable — this is a file-verification and archive-extraction utility,
not a visual component.

## Accessibility

Not applicable — this is a file-verification and archive-extraction utility,
not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| vsix-archive-001 | sha256-hex-format | `VSIXArchive.sha256Hex(of: Data("the archive".utf8))` | Returns lowercase hex equal to `SHA256.hash(data:)` of the same bytes, joined as `%02x` (test `digestIsOfTheBytes`) |
| vsix-archive-002 | digest-comparison-normalized, digest-match-result | `verify(bytes, expectedDigest: "  \(digest.uppercased())\n", signature: nil, publicKeyPEM: nil)` | Returns `digest: .matched`, `sha256 == digest` (test `digestComparisonIsForgivingAboutFormatting`) |
| vsix-archive-003 | digest-mismatch | `verify(bytes, expectedDigest: String(repeating: "a", count: 64), signature: nil, publicKeyPEM: nil)` | Throws `VSIXVerificationError.digestMismatch(expected: "aaa...", actual: sha256Hex(of: bytes))` (test `digestMismatchThrows`) |
| vsix-archive-004 | digest-not-published-result, signature-neither-published | `verify(bytes, expectedDigest: nil, signature: nil, publicKeyPEM: nil)` | Returns `digest: .notPublished`, `signature: .notPublished`, `sha256 == sha256Hex(of: bytes)` (test `noDigestStillHashes`) |
| vsix-archive-005 | signature-verified-with-real-key | `verify(bytes, expectedDigest: sha256Hex(of: bytes), signature: sigzip, publicKeyPEM: key)` with a real Ed25519 signature over `bytes` | Returns `signature: .registryAttested` (test `signatureVerifies`) |
| vsix-archive-006 | signature-invalid | `verify(substituted, expectedDigest: sha256Hex(of: substituted), signature: sigzip, publicKeyPEM: key)` where `sigzip`/`key` sign a different byte string than `substituted` | Throws `VSIXVerificationError.signatureInvalid` (test `signatureOverOtherBytesIsRefused`) |
| vsix-archive-007 | signature-invalid | `verify` with a `.sigzip` whose `.signature.sig` bytes were corrupted after signing | Throws `VSIXVerificationError.signatureInvalid` (test `corruptedSignatureIsRefused`) |
| vsix-archive-008 | signature-half-pair-refused | `verify(bytes, expectedDigest: nil, signature: sigzip, publicKeyPEM: nil)` | Throws `VSIXVerificationError.signatureIncomplete(missing: "publicKey")` (test `halfThePairIsRefused`) |
| vsix-archive-009 | signature-half-pair-refused | `verify(bytes, expectedDigest: nil, signature: nil, publicKeyPEM: key)` | Throws `VSIXVerificationError.signatureIncomplete(missing: "signature")` (test `halfThePairIsRefused`) |
| vsix-archive-010 | public-key-parsing | `verify` with `publicKeyPEM` set to a PEM block whose body is not valid base64 | Throws `VSIXVerificationError.publicKeyUnreadable` (test `unreadablePublicKey`) |
| vsix-archive-011 | public-key-parsing | `verify` with `publicKeyPEM` set to a PEM block that decodes to 64 bytes, not the required 44 | Throws `VSIXVerificationError.publicKeyUnreadable` (test `unreadablePublicKey`) |
| vsix-archive-012 | signature-archive-extraction | `verify` with a `signature` `.sigzip` containing only an unrelated `readme.txt`, no `.signature.sig` | Throws an error (`signatureArchiveUnreadable`, via `emptySignatureArchive`'s `#expect(throws: (any Error).self)`) |
| vsix-archive-013 | digest-checked-before-signature | `verify(bytes, expectedDigest: wrongDigest, signature: sigzip, publicKeyPEM: key)` where `sigzip`/`key` would otherwise verify | Throws `VSIXVerificationError.digestMismatch`, not a signature error (test `digestIsCheckedFirst`) |
| vsix-archive-014 | expand-uses-ditto, expand-success-preserves-destination | `expand(archive, to: expanded)` on an archive built from a staging directory holding `extension/package.json` | `payloadDirectory(in: expanded)/package.json` exists after the call (test `expandProducesThePayload`) |
| vsix-archive-015 | expand-destination-must-not-exist | `expand(archive, to: destination)` where `destination` already exists as a directory | Throws `VSIXArchiveError.destinationExists(destination)` (test `expandRefusesAnExistingDestination`) |
| vsix-archive-016 | expand-nonzero-status-cleanup, expand-cleanup-is-best-effort | `expand` on a file that is not a valid zip archive | Throws an error and `destination` does not exist afterward (test `failedExpansionCleansUp`) |
| vsix-archive-017 | expand-byte-ceiling-watchdog, expand-abort-cleanup | `expand(archive, to: destination, byteCeiling: 1_048_576, checkInterval: 0.005)` on an archive that expands to 64 MB | Throws `VSIXArchiveError.expansionTooLarge(bytes: 1_048_576)`; `destination` does not exist afterward (test `anOversizeExpansionIsStopped`) |
| vsix-archive-018 | expand-byte-ceiling-watchdog | Same archive shape, `byteCeiling: 67_108_864, checkInterval: 0.005` | Completes without throwing; `payloadDirectory(in: destination)/package.json` exists (test `anOrdinaryExpansionIsNotStopped`) |
| vsix-archive-019 | byte-ceiling-exceeds-artifact-cap | Compare `VSIXArchive.expansionByteCeiling` and `OpenVSXClient.defaultMaximumArtifactBytes` | `expansionByteCeiling > Int64(defaultMaximumArtifactBytes)` (test `theDefaultCeilingIsAboveTheDownloadCap`) |
| vsix-archive-020 | expand-path-traversal-containment | `expand` an archive with entries `extension/package.json` and a relatively-named `../escaped.txt` | `escaped.txt` does not exist one level above `destination`; it exists inside `destination` (test `aRelativeTraversalIsFlattened`) |
| vsix-archive-021 | expand-path-traversal-containment | `expand` an archive with an entry named by an absolute path inside the test's own scratch directory | The absolute target does not exist; the same path, re-rooted under `destination`, does exist (test `anAbsoluteNameIsReRooted`) |
| vsix-archive-022 | expand-symlink-escape-failure, expand-nonzero-status-cleanup | `expand` an archive containing a symlink entry pointing outside `destination` followed by an entry written through it | Throws `VSIXArchiveError.expansionFailed(status:, message:)` with `status != 0` and a non-empty `message`; the file is not planted outside, and `destination` does not exist (test `aSymlinkWrittenThroughFailsTheExpansion`) |
| vsix-archive-023 | expand-timeout-cleanup | `expand(archive, to: destination, timeout: 0.001)` | Throws `VSIXArchiveError.expansionTimedOut(seconds: 0.001)`; `destination` does not exist afterward (test `anExpansionThatOutlastsItsBudgetIsStopped`) |
| vsix-archive-024 | expand-default-parameters | Compare `VSIXArchive.expansionTimeout` to the published default | Equals `120` (test `theDefaultBudgetIsThePublishedOne`) |
| vsix-archive-025 | expand-uses-ditto, expand-success-preserves-destination | `expand` a hand-built archive containing only `extension/package.json` with content `{"name": "widget"}` | The expanded `package.json` at `payloadDirectory(in: destination)` reads back exactly `{"name": "widget"}` (test `theHandBuiltArchiveIsValid`) |

## Edge Cases

- **Null and empty input**: An `archive` of zero-length `Data` passed to
  `verify` MUST still be hashed successfully by `sha256Hex(of:)`, which is a
  total function over any `Data` value; nothing in `verify` special-cases
  emptiness (`digest-always-hashed`). An `archive` `URL` in `expand` pointing
  at a zero-byte file is not a valid zip, so `ditto` MUST exit non-zero and
  `expand` MUST throw `VSIXArchiveError.expansionFailed` with `destination`
  removed, the same path exercised by `failedExpansionCleansUp`
  (`expand-nonzero-status-cleanup`).
- **Boundary values**: A decompressed tree whose measured size is exactly
  equal to `byteCeiling` MUST NOT abort the run — only a running total
  strictly greater than `ceiling` triggers the watchdog (`if total > ceiling`); a `publicKeyPEM` that decodes to exactly
  `ed25519SPKILength` (44) bytes MUST be accepted, and any other length MUST
  be refused (`public-key-parsing`); a `.signature.sig` of exactly
  `ed25519SignatureLength` (64) bytes MUST be accepted, and any other length
  MUST be refused (`signature-archive-extraction`).
- **concurrent-access**: NEEDS REVIEW: Not implemented in source. Two concurrent calls to `expand` given the same `destination` URL are not serialized against each other — no lock or exclusive-create primitive guards the check-then-create sequence, since `FileManager.default.createDirectory(at:withIntermediateDirectories: true)` does not throw when the directory already exists, so both callers can pass the `!fileExists` guard and then run two `ditto` processes writing into the same directory concurrently with no defined outcome for which files survive; resolving this needs either a doc-comment contract requiring a fresh `destination` per call or a lock/atomic-create primitive — today's only caller, `VSIXInstaller`, always supplies a fresh `UUID`-named `destination` per install, which does not settle what `expand` itself guarantees.

  Calls to `verify`, and calls to `expand` with distinct `destination` values,
  remain independent (`concurrent-calls-independent-when-destinations-differ`).
- **Error states (dependency unavailable)**: When `/usr/bin/ditto` cannot be
  launched at all — for example if it were removed or unexecutable —
  `CommandRunner.runToCompletion` throws, and `expand` MUST report this as
  `VSIXArchiveError.expansionUnavailable(String(describing: error))` with
  `destination` removed (`expand-launch-failure-cleanup`). This is the only
  form "a dependency is unavailable" takes for this component, since it
  performs no network I/O of its own.
- **Offline / disconnected state**: Not applicable — `VSIXArchive` performs
  no network I/O; it operates entirely on `archive` bytes or a local
  `archive` file URL the caller already has in hand, and its only imports are
  `CryptoKit`, `Foundation`, and `OSLog`. Connectivity is a
  concern for whichever caller downloaded the archive before calling
  `verify` or `expand`.
- **Malformed input (not a zip)**: An `archive` file that is not a valid zip
  MUST cause `ditto` to exit non-zero, reported as
  `VSIXArchiveError.expansionFailed(status:message:)` with `destination`
  removed (test `failedExpansionCleansUp`). A `signature` `.sigzip` that is
  not a valid zip MUST be caught inside `signatureBytes(fromSigZip:)`'s
  `do`/`catch` and rethrown as
  `VSIXVerificationError.signatureArchiveUnreadable`, since `expand` is
  called on it internally and any error it throws is caught there.
- **Malformed input (hostile archive entries)**: A relative-traversal entry
  name, an absolute entry name, and a symlink written through are each
  handled as their own requirement rather than left unvalidated
  (`expand-path-traversal-containment`, `expand-symlink-escape-failure`); the
  containment is `ditto`'s own, not code in this file, which the doc comment
  states explicitly rather than claiming credit for a hand-rolled check
  (doc comment).
- **Cancellation**: `verify` and `expand` are synchronous, non-`async`
  functions with no `Task` and no cooperative cancellation check anywhere in
  the source; the only way `expand` itself gives up early is its own
  `timeout` or `byteCeiling`, enforced by `CommandRunner.runToCompletion`'s
  polling loop (`synchronous-blocking-execution`,
  `expand-byte-ceiling-watchdog`). A caller that wraps either call in a
  cancellable `Task` and cancels it MUST wait for the underlying blocking
  call to return on its own before the cancellation is observed, since
  neither function checks `Task.isCancelled`.
- **Timeout**: An `expand` run that exceeds `timeout` MUST be terminated by
  `CommandRunner`, reported as `VSIXArchiveError.expansionTimedOut(seconds:)`,
  and MUST leave no directory at `destination` (`expand-timeout-cleanup`;
  test `anExpansionThatOutlastsItsBudgetIsStopped`). A `.vsix` that
  decompresses past `byteCeiling` faster than it exceeds `timeout` is stopped
  by the byte ceiling first and reported as `expansionTooLarge`, not as a
  timeout (`expand-abort-cleanup`; test `anOversizeExpansionIsStopped`) —
  the two limits guard different axes and either can fire without the other
  (doc comment on `expansionByteCeiling`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `expectedDigest` (`verify` parameter) | `String?` | — (required parameter, no default) | The registry-published SHA-256 hex digest to compare the archive against; `nil` means the registry published none. |
| `signature` (`verify` parameter) | `Data?` | — (required parameter, no default) | The registry-published `.sigzip` bytes; `nil` means no signature was published. |
| `publicKeyPEM` (`verify` parameter) | `String?` | — (required parameter, no default) | The registry-published Ed25519 public key, PEM-encoded SPKI; `nil` means no key was published. |
| `timeout` (`expand` parameter) | `TimeInterval` | `VSIXArchive.expansionTimeout` (120 seconds) | How long `ditto` is given to finish before the run is terminated and reported as timed out. |
| `byteCeiling` (`expand` parameter) | `Int64` | `VSIXArchive.expansionByteCeiling` (2,147,483,648 bytes) | How much allocated disk space may land under `destination` before the run is aborted and reported as too large. |
| `checkInterval` (`expand` parameter) | `TimeInterval` | `VSIXArchive.expansionCheckInterval` (0.5 seconds) | How often `destination`'s size is measured against `byteCeiling` while `ditto` runs. |

## Deep Linking

Not applicable: `VSIXArchive` defines no navigable route, screen, or URL
scheme of its own — every `URL` it touches is either a local archive file
path or the caller-supplied `destination` directory, never a route this app
presents to a person (traced to the full source, which declares no route or
scheme type of any kind).

## Localization

Not applicable: the source declares no user-facing string literal.
`VSIXVerificationError` and `VSIXArchiveError` carry structured data — a
digest string, a byte count, a duration, an `Int32` status, or `ditto`'s raw
diagnostic text — rather than display text authored by this type, and no
function returns or logs a message meant to be read by a person (traced to
the `VSIXVerificationError` and `VSIXArchiveError` enums, and
to the absence of any display-text literal in `verify` or `expand`).

## Accessibility Options

Not applicable: this is a non-visual archive-verification and extraction
utility with no rendered UI to respond to Reduce Motion, Increase Contrast,
or Differentiate Without Color (traced to the full source, which contains no
UI code of any kind).

## Feature Flags

Not applicable: the source declares no feature-flag or configuration-flag
lookup — every call to `verify` or `expand` runs the same fixed logic
unconditionally on every invocation (traced to the absence of any flag check
anywhere in the source).

## Analytics

Not applicable: the source contains no event-emission or telemetry call of
any kind — `verify` and `expand` return a value or throw directly to the
caller, with no recorded event (traced to the full body of the source file).

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

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default) |
Category: `VSIXArchive`

| Event | Level | Message |
|-------|-------|---------|
| — | — | Not emitted: `VSIXArchive` conforms to `Loggable` and declares `public static nonisolated let logger = makeLogger()`, but no function in the source calls `logger` — every failure is communicated to the caller as a thrown `VSIXVerificationError` or `VSIXArchiveError` case instead of a log line. |

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

## Design Decisions

**Decision**: Shell out to `/usr/bin/ditto -x -k` rather than a Swift or
third-party zip library for extraction.
**Rationale**: It is the platform's own unarchiver — the same one a Finder
double-click runs — and it already refuses the two ways a hostile archive
escapes its destination (a traversing relative or absolute entry name, and a
symlink written through), checked here against a purpose-built archive
rather than assumed. A pure-Swift unzip would have had to re-earn both, and
getting either subtly wrong is a directory traversal in a path that takes
third-party archives off the internet (doc comment).
**Approved**: pending

**Decision**: Bound `expand` on two independent axes — a wall-clock
`timeout` and a decompressed-size `byteCeiling` — rather than one.
**Rationale**: A zip bomb is a compression ratio, not a duration: the
canonical ones write tens of gigabytes as fast as the disk accepts them and
then exit cleanly well inside a two-minute timeout, which is why the timeout
alone was previously (incorrectly) described as covering this case. The
ceiling and the timeout each catch an archive the other does not — one that
never finishes, and one that finishes by filling the disk (doc comment on
`expansionTimeout`; doc comment on `expansionByteCeiling`).
**Approved**: pending

**Decision**: Set `expansionByteCeiling` to 2 GiB, several times the size of
the largest real extension known to bundle a per-platform language-server
binary, rather than a tighter number closer to typical extension size.
**Rationale**: Deflate reaches roughly 1000:1 compression on adversarial
input, so the 512 MB `OpenVSXClient` artifact download cap alone is license
to decompress to half a terabyte; 2 GiB is comfortably above any honest
extension while remaining small enough that reaching it leaves room on the
volume to report the failure (doc comment).
**Approved**: pending

**Decision**: Name a fully verified result `.registryAttested` rather than
`.verified`, and treat a signature/key pair from the registry as proving the
bytes were not altered in transit — never as proving who published them.
**Rationale**: `publicKeyPEM` arrives from `OpenVSXExtensionDetail
.publicKeyURL`, a string in the same JSON response that named the archive
and its digest; a registry serving altered bytes signs them with a key of
its own, publishes that key at that URL, and every check in `verify` passes.
There is no anchor to compare the key against — Open VSX publishes no
publisher key out of band, and this host has pinned none — so the settings
panel line this result feeds has to say "the registry published," not "the
publisher signed" (doc comment).
**Approved**: pending

**Decision**: Throw on a signature or key published alone, rather than
treating the pair as absent.
**Rationale**: Most of Open VSX is unsigned, so refusing every unsigned
extension would refuse the catalog — but one half of the pair present is a
different situation from neither being present: something *was* published,
and reporting that as an unsigned extension states the opposite of what
happened. The thrown `signatureIncomplete(missing:)` names which half is
missing, which is the fact a report against the registry needs (doc comment).
**Approved**: pending

**Decision**: Check the digest before the signature, and always compute
`sha256Hex(of:)` regardless of whether a digest to compare it against was
published.
**Rationale**: A digest mismatch is reported as a digest failure even when a
signature would otherwise verify, because a truncated or substituted
download is a different situation from a signing problem and should send
whoever reads the error looking at their network, not the publisher's key
(test `digestIsCheckedFirst`). The hash is still computed when no digest was
published because an install record needs it to recognize these exact bytes
later, but its presence must not be read as "these bytes were checked" —
hence the separate `.matched`/`.notPublished` result rather than inferring a
check from the hash's presence (doc comment).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | partial | Reliability |

`separation-of-concerns` passes: `VSIXArchive` delegates process execution,
draining, and deadline enforcement to `CommandRunner`, and delegates the
actual containment of hostile archive entries to `/usr/bin/ditto`, keeping
its own code to hashing, digest/signature comparison, status interpretation,
and cleanup (`stateless-namespace`, Overview). `unit-test-coverage` passes:
23 test functions across `VSIXArchiveTests.swift` (17) and
`VSIXArchiveContainmentTests.swift` (6) exercise every `verify` outcome —
digest match, mismatch, absent, both signature halves, a real Ed25519
signature, an invalid one, a corrupted one, an unreadable key, an unreadable
signature archive, and ordering between the two checks — and every `expand`
outcome, including the timeout path, the byte-ceiling path, a non-zip
archive, an existing destination, a relative-traversal entry, an
absolute-path entry, and a symlink written through. `explicit-error-handling`
passes: every failure mode this type detects raises a specific, `Equatable`
`VSIXVerificationError` or `VSIXArchiveError` case rather than returning
`nil` or continuing silently, with the one documented exception —
`try?`-based best-effort cleanup of a partially written `destination` on a
failure path — stated plainly as its own requirement
(`expand-cleanup-is-best-effort`) rather than hidden. `input-sanitization`
passes: `expand` refuses to let a hostile entry name or a symlink written
through place bytes outside `destination`, treating every archive it
extracts as untrusted input from the internet (`expand-path-traversal-
containment`, `expand-symlink-escape-failure`; `VSIXArchiveContainmentTests`).
`data-integrity` passes: `verify` checks the archive's digest and signature
against what the registry published before any caller treats the bytes as
authentic, and every case is `Equatable` so a mismatch is detected and
reported rather than assumed away. `timeout-handling` passes: both the
`timeout` and `byteCeiling` limits leave `destination` in a consistent
state — removed, never partially written — when either fires
(`expand-timeout-cleanup`, `expand-abort-cleanup`). `fault-tolerance` is
partial: the type does handle a hostile or malformed archive without
crashing (a non-zip file, a zip bomb, a traversing or symlinked entry all
throw or fail cleanly), but concurrent calls to `expand` sharing the same
`destination` are not guarded against, which is the open question on
`concurrent-access`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
