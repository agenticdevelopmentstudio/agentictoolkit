---
id: dbe4b3b6-ac5b-4d45-ba2a-84aad1a8582e
title: VSIX Archive
domain: agentictoolkit://cookbook/workspace/extensions/registry/vsix-archive
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Proves a downloaded .vsix's bytes against a registry-published digest
  and signature, then expands it to disk through a timed, size-bounded archive
  extraction."
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
- agentictoolkit://cookbook/workspace/extensions/registry/open-vsx-client
references:
- packages/apple/AgenticToolkit/Core/Extensions/VSIXArchive.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Process/CommandRunner.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# VSIX Archive

## Overview

The VSIX archive concept is a stateless collection of two operations on a
downloaded `.vsix` file: verification, which checks the raw archive bytes
against whatever digest and Ed25519 signature the registry published for
them, and expansion, which unpacks the archive onto disk through the
platform's own archive-extraction utility under a timeout and a
decompressed-size ceiling. A `.vsix` is a zip whose extension tree lives
under an `extension/` subdirectory alongside packaging metadata this host
does not read; resolving the payload directory is the one place that
subdirectory name is spelled out.

Both operations are read-only with respect to the network: nothing here
downloads anything. The one caller in this codebase fetches the archive
bytes and the optional digest/signature/key text over HTTP itself, then
calls verification followed by expansion synchronously, inside a dedicated
blocking-work context, because neither operation suspends and both can hold
a thread for the length of a 512 MB download's worth of hashing or an
extraction run.

Verification's contract states plainly what its two checks do and do not
establish: the digest and signature are both checked against values the
*registry* published in the same response that named the archive, never
against an out-of-band publisher key, so a registry serving altered bytes
under a key of its own passes every check here. That is why a fully
verified result is named "registry attested" rather than "verified."

## Behavioral Requirements

- **payload-directory-name**: The archive's payload-directory name MUST
  equal `"extension"`.
- **payload-directory-path**: Resolving the payload directory within an
  expanded tree MUST return the expanded root with the payload-directory
  name appended as a path component.
- **sha256-hex-format**: Computing the SHA-256 digest of a byte sequence
  MUST return it as lowercase hexadecimal, MUST be deterministic for the
  same bytes, and MUST differ for different bytes.
- **digest-always-hashed**: Verification MUST compute the SHA-256 digest of
  the archive and return it as the verification result's digest value on
  every call, whether or not an expected digest is supplied.
- **digest-comparison-normalized**: When an expected digest is supplied,
  verification MUST trim it of leading and trailing whitespace and newline
  characters and lowercase it before comparing to the computed hash.
- **digest-mismatch**: Verification MUST fail with a digest-mismatch error,
  carrying the normalized expected digest and the computed digest, when the
  two do not match, and MUST NOT evaluate the signature in that case.
- **digest-match-result**: When the normalized expected digest equals the
  computed hash, verification's returned digest-status MUST be "matched."
- **digest-not-published-result**: When no expected digest is supplied,
  verification's returned digest-status MUST be "not published," distinct
  from "matched," even though the digest value is still filled in.
- **digest-checked-before-signature**: Verification MUST evaluate the
  digest before evaluating the signature, so a digest mismatch is reported
  as a digest-mismatch error even when a signature and key are also
  supplied and would otherwise verify.
- **signature-neither-published**: When neither a signature nor a public
  key is supplied, verification MUST succeed and return signature-status
  "not published" rather than failing.
- **signature-half-pair-refused**: When exactly one of the signature or the
  public key is supplied, verification MUST fail with a
  signature-incomplete error naming the missing half as `"publicKey"` or
  `"signature"` respectively, without attempting any cryptographic check.
- **signature-verified-with-real-key**: When both a signature and a public
  key are supplied, verification MUST extract the raw signature bytes from
  the signature archive and the Ed25519 public key from the PEM-encoded key
  text, and MUST check the signature against the archive's bytes, returning
  signature-status "registry attested" on success.
- **signature-invalid**: Verification MUST fail with a signature-invalid
  error when the extracted signature does not validate against the archive
  under the extracted key — whether because the bytes being verified were
  substituted or the signature bytes were corrupted.
- **signature-manifest-and-p7s-ignored**: Verification MUST verify the
  signature against the archive's bytes directly, using only the signature
  archive's `.signature.sig` entry; it MUST NOT read or verify a
  `.signature.manifest` or `.signature.p7s` entry, the other two entries the
  signature archive may carry.
- **signature-archive-extraction**: Extracting the signature bytes from the
  signature archive MUST write the signature archive's bytes to a scratch
  location, expand it, and read exactly the Ed25519 signature length (64)
  bytes from its `.signature.sig` entry, failing with a
  signature-archive-unreadable error carrying a diagnostic string when that
  entry is absent or is not exactly 64 bytes, or when writing or expanding
  the scratch archive itself fails.
- **signature-scratch-cleanup**: Extracting the signature bytes MUST remove
  its scratch location on every exit path, whether extraction succeeded or
  failed.
- **public-key-parsing**: Parsing the public key from PEM text MUST strip
  header/footer lines (lines starting `-----`) and newline characters,
  base64-decode the remainder, and require exactly the Ed25519 SPKI length
  (44) decoded bytes, taking the last Ed25519 key length (32) bytes as the
  raw key; anything that fails base64 decoding or is not exactly 44 bytes,
  or whose final 32 bytes are refused as an Ed25519 key, MUST fail with a
  public-key-unreadable error.
- **expand-destination-must-not-exist**: Expansion MUST fail with a
  destination-exists error, naming the destination, without creating any
  directory or launching any process, when the destination already exists.
- **expand-destination-created**: When the destination does not already
  exist, expansion MUST create it, with intermediate directories, before
  extraction begins.
- **expand-uses-ditto**: Expansion MUST delegate the actual unpacking to
  the platform's own archive-extraction utility, given the archive path and
  the destination path, rather than an implemented zip reader.
- **expand-default-parameters**: Expansion's timeout, byte-ceiling, and
  check-interval parameters MUST default to 120 seconds, 2,147,483,648
  bytes, and 0.5 seconds respectively.
- **expand-byte-ceiling-watchdog**: Expansion MUST poll the destination's
  measured expanded size every check-interval and abort the run as soon as
  that measurement exceeds the byte ceiling.
- **expand-timeout-cleanup**: When the run times out, expansion MUST
  attempt to remove the destination and MUST fail with an
  expansion-timed-out error naming the configured timeout.
- **expand-abort-cleanup**: When the run is aborted for exceeding the byte
  ceiling, expansion MUST attempt to remove the destination and MUST fail
  with an expansion-too-large error naming the configured byte ceiling.
- **expand-nonzero-status-cleanup**: When the run neither times out nor is
  aborted but exits with a non-zero status, expansion MUST attempt to
  remove the destination and MUST fail with an expansion-failed error
  carrying that status and the extraction process's trimmed diagnostic
  output.
- **expand-launch-failure-cleanup**: When the extraction process itself
  cannot be launched, expansion MUST attempt to remove the destination and
  MUST fail with an expansion-unavailable error describing the failure.
- **expand-cleanup-is-best-effort**: Every removal of the destination on a
  failure path MUST be attempted without propagating a secondary error, so
  a failure to delete the partially written tree is discarded silently and
  never masks or replaces the original failure.
- **expand-success-preserves-destination**: When the run exits with a zero
  status and neither times out nor is aborted, expansion MUST leave the
  fully expanded tree in place at the destination and MUST NOT remove it.
- **expand-path-traversal-containment**: Expansion MUST NOT allow an
  archive entry named with a relative traversal (for example
  `../escaped.txt`) or an absolute path (for example `/tmp/x`) to write
  outside the destination; both forms MUST land inside the destination,
  flattened or re-rooted, because the platform's own extraction utility
  provides this containment and expansion neither disables nor duplicates
  it.
- **expand-symlink-escape-failure**: When an archive entry is a symbolic
  link pointing outside the destination, followed by an entry written
  through that link, expansion MUST fail the whole run with a non-zero
  exit status — reported as an expansion-failed error — rather than
  complete with the write silently redirected outside the destination.
- **expanded-size-measurement**: Measuring the expanded size of a directory
  tree MUST sum each item's allocated size (falling back to logical size
  when allocated size is unavailable), walking a directory bundle as
  ordinary files rather than skipping it as an opaque package, and MUST
  return as soon as the running total exceeds the supplied ceiling without
  continuing to walk the rest of the tree.
- **byte-ceiling-exceeds-artifact-cap**: The expansion byte ceiling MUST be
  greater than the registry client's maximum download size, so the
  decompressed-size ceiling this concept enforces is never tighter than the
  compressed-size ceiling the archive was already downloaded under.
- **stateless-namespace**: This concept MUST be a stateless collection of
  operations with no instance, holding only fixed constants and functions
  and no stored instance state of any kind — it can never be instantiated,
  so it carries no per-call or shared mutable state and requires no
  explicit concurrency-safety declaration to be safe to call from any
  concurrent context.
- **synchronous-blocking-execution**: Verification and expansion MUST both
  run synchronously to completion with no suspension point; verification
  performs its digest and signature work, and expansion waits for the
  extraction process to finish for up to the configured timeout plus grace
  periods, entirely on the calling thread.
- **concurrent-calls-independent-when-destinations-differ**: Concurrent
  calls to verification, or to expansion with distinct destination values,
  MUST run independently with no shared state between them: verification
  reads only its arguments, and each expansion or signature-extraction call
  creates its own process and, for signature extraction, its own
  uniquely-named scratch location.
- **logging-conformance-declared-unused**: This concept MUST participate
  in the host's logging convention, declaring a logger scoped to its own
  category, but no operation in it actually calls that logger — every
  failure surfaces to the caller as a distinct error case instead of a log
  line.
- **error-cases-carry-diagnostic-data**: Every archive-expansion error case
  except destination-exists MUST carry data identifying why the run was
  stopped — a message, a byte count, or a duration — rather than a bare
  case with no payload, so a report against a failed install names what
  happened.

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
| vsix-archive-001 | sha256-hex-format | Compute the digest of the bytes `"the archive"` | Returns lowercase hex equal to the SHA-256 digest of the same bytes |
| vsix-archive-002 | digest-comparison-normalized, digest-match-result | Verify with the expected digest supplied as the correct digest, uppercased and padded with leading/trailing whitespace and a trailing newline | Returns digest-status "matched," with the digest value equal to the expected digest |
| vsix-archive-003 | digest-mismatch | Verify with an expected digest of 64 repeated `"a"` characters | Fails with a digest-mismatch error carrying the expected value and the actual computed digest |
| vsix-archive-004 | digest-not-published-result, signature-neither-published | Verify with no expected digest, no signature, and no public key | Returns digest-status "not published," signature-status "not published," and the digest value equal to the computed digest |
| vsix-archive-005 | signature-verified-with-real-key | Verify with the correct digest, a signature archive, and a public key, where the signature is a real Ed25519 signature over the archive bytes | Returns signature-status "registry attested" |
| vsix-archive-006 | signature-invalid | Verify substituted bytes with a digest, signature, and key that sign a different byte string than the substituted bytes | Fails with a signature-invalid error |
| vsix-archive-007 | signature-invalid | Verify with a signature archive whose `.signature.sig` bytes were corrupted after signing | Fails with a signature-invalid error |
| vsix-archive-008 | signature-half-pair-refused | Verify with no expected digest, a signature archive, and no public key | Fails with a signature-incomplete error naming `"publicKey"` |
| vsix-archive-009 | signature-half-pair-refused | Verify with no expected digest, no signature, and a public key | Fails with a signature-incomplete error naming `"signature"` |
| vsix-archive-010 | public-key-parsing | Verify with a public key whose PEM body is not valid base64 | Fails with a public-key-unreadable error |
| vsix-archive-011 | public-key-parsing | Verify with a public key whose PEM body decodes to 64 bytes, not the required 44 | Fails with a public-key-unreadable error |
| vsix-archive-012 | signature-archive-extraction | Verify with a signature archive containing only an unrelated `readme.txt`, no `.signature.sig` | Fails with a signature-archive-unreadable error |
| vsix-archive-013 | digest-checked-before-signature | Verify with a wrong expected digest, alongside a signature and key that would otherwise verify | Fails with a digest-mismatch error, not a signature error |
| vsix-archive-014 | expand-uses-ditto, expand-success-preserves-destination | Expand an archive built from a staging directory holding `extension/package.json` | The payload directory's `package.json` exists after the call |
| vsix-archive-015 | expand-destination-must-not-exist | Expand to a destination that already exists as a directory | Fails with a destination-exists error naming the destination |
| vsix-archive-016 | expand-nonzero-status-cleanup, expand-cleanup-is-best-effort | Expand a file that is not a valid archive | Fails, and the destination does not exist afterward |
| vsix-archive-017 | expand-byte-ceiling-watchdog, expand-abort-cleanup | Expand, with a byte ceiling of 1,048,576 and a check interval of 0.005 seconds, an archive that expands to 64 MB | Fails with an expansion-too-large error naming 1,048,576; the destination does not exist afterward |
| vsix-archive-018 | expand-byte-ceiling-watchdog | Same archive shape, byte ceiling 67,108,864, check interval 0.005 seconds | Completes without failing; the payload directory's `package.json` exists |
| vsix-archive-019 | byte-ceiling-exceeds-artifact-cap | Compare the expansion byte ceiling and the registry client's maximum download size | The expansion byte ceiling is greater |
| vsix-archive-020 | expand-path-traversal-containment | Expand an archive with entries `extension/package.json` and a relatively-named `../escaped.txt` | `escaped.txt` does not exist one level above the destination; it exists inside the destination |
| vsix-archive-021 | expand-path-traversal-containment | Expand an archive with an entry named by an absolute path inside the test's own scratch directory | The absolute target does not exist; the same path, re-rooted under the destination, does exist |
| vsix-archive-022 | expand-symlink-escape-failure, expand-nonzero-status-cleanup | Expand an archive containing a symlink entry pointing outside the destination followed by an entry written through it | Fails with an expansion-failed error carrying a non-zero status and a non-empty message; the file is not planted outside, and the destination does not exist |
| vsix-archive-023 | expand-timeout-cleanup | Expand with a timeout of 0.001 seconds | Fails with an expansion-timed-out error naming 0.001 seconds; the destination does not exist afterward |
| vsix-archive-024 | expand-default-parameters | Compare the default expansion timeout to the published default | Equals 120 |
| vsix-archive-025 | expand-uses-ditto, expand-success-preserves-destination | Expand a hand-built archive containing only `extension/package.json` with content `{"name": "widget"}` | The expanded `package.json` at the payload directory reads back exactly `{"name": "widget"}` |

## Edge Cases

- **Null and empty input**: An archive of zero-length bytes passed to
  verification MUST still be hashed successfully — digest computation is a
  total function over any byte sequence; nothing in verification
  special-cases emptiness (**digest-always-hashed**). An archive file that
  is a zero-byte file is not a valid archive, so the extraction utility
  MUST exit non-zero and expansion MUST fail with an expansion-failed error
  with the destination removed, the same path exercised for any non-zip
  input (**expand-nonzero-status-cleanup**).
- **Boundary values**: A decompressed tree whose measured size is exactly
  equal to the byte ceiling MUST NOT abort the run — only a running total
  strictly greater than the ceiling triggers the watchdog; a public key
  that decodes to exactly the Ed25519 SPKI length (44) bytes MUST be
  accepted, and any other length MUST be refused (**public-key-parsing**);
  a signature-archive entry of exactly the Ed25519 signature length (64)
  bytes MUST be accepted, and any other length MUST be refused
  (**signature-archive-extraction**).
- **concurrent-access**: NEEDS REVIEW: Not implemented in source. Two
  concurrent expansion calls given the same destination are not serialized
  against each other — no lock or exclusive-create primitive guards the
  check-then-create sequence, since directory creation does not fail when
  the directory already exists, so both callers can pass the existence
  guard and then run two extraction processes writing into the same
  directory concurrently with no defined outcome for which files survive;
  resolving this needs either a documented contract requiring a fresh
  destination per call or a lock/atomic-create primitive — today's only
  caller always supplies a fresh, uniquely-named destination per install,
  which does not settle what expansion itself guarantees.

  Calls to verification, and calls to expansion with distinct destination
  values, remain independent
  (**concurrent-calls-independent-when-destinations-differ**).
- **Error states (dependency unavailable)**: When the platform's extraction
  utility cannot be launched at all — for example if it were removed or
  unexecutable — expansion MUST report this as an expansion-unavailable
  error with the destination removed (**expand-launch-failure-cleanup**).
  This is the only form "a dependency is unavailable" takes for this
  component, since it performs no network I/O of its own.
- **Offline / disconnected state**: Not applicable — this concept performs
  no network I/O; it operates entirely on archive bytes or a local archive
  file the caller already has in hand. Connectivity is a concern for
  whichever caller downloaded the archive before calling verification or
  expansion.
- **Malformed input (not a zip)**: An archive file that is not a valid
  archive MUST cause the extraction utility to exit non-zero, reported as
  an expansion-failed error with the destination removed. A signature
  archive that is not a valid archive MUST be caught during signature-bytes
  extraction and reported as a signature-archive-unreadable error, since
  expansion is invoked on it internally and any failure it produces is
  caught there.
- **Malformed input (hostile archive entries)**: A relative-traversal
  entry name, an absolute entry name, and a symlink written through are
  each handled as their own requirement rather than left unvalidated
  (**expand-path-traversal-containment**, **expand-symlink-escape-failure**);
  the containment is the platform extraction utility's own, not logic in
  this concept, which is stated explicitly rather than claiming credit for
  a hand-rolled check.
- **Cancellation**: Verification and expansion are synchronous operations
  with no cooperative cancellation check anywhere; the only way expansion
  itself gives up early is its own timeout or byte ceiling, enforced by the
  polling loop (**synchronous-blocking-execution**,
  **expand-byte-ceiling-watchdog**). A caller that wraps either call in a
  cancellable unit of work and cancels it MUST wait for the underlying
  blocking call to return on its own before the cancellation is observed,
  since neither operation checks for cancellation itself.
- **Timeout**: An expansion run that exceeds its timeout MUST be
  terminated, reported as an expansion-timed-out error, and MUST leave no
  directory at the destination (**expand-timeout-cleanup**). An archive
  that decompresses past the byte ceiling faster than it exceeds the
  timeout is stopped by the byte ceiling first and reported as
  expansion-too-large, not as a timeout (**expand-abort-cleanup**) — the
  two limits guard different axes and either can fire without the other.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| expectedDigest (verification parameter) | an optional string | none — required parameter | The registry-published SHA-256 hex digest to compare the archive against; absent means the registry published none. |
| signature (verification parameter) | optional bytes | none — required parameter | The registry-published signature-archive bytes; absent means no signature was published. |
| publicKeyPEM (verification parameter) | an optional string | none — required parameter | The registry-published Ed25519 public key, PEM-encoded; absent means no key was published. |
| timeout (expansion parameter) | a duration | 120 seconds | How long the extraction utility is given to finish before the run is terminated and reported as timed out. |
| byteCeiling (expansion parameter) | a byte count | 2,147,483,648 bytes | How much allocated disk space may land under the destination before the run is aborted and reported as too large. |
| checkInterval (expansion parameter) | a duration | 0.5 seconds | How often the destination's size is measured against the byte ceiling while extraction runs. |

## Deep Linking

Not applicable: this concept defines no navigable route, screen, or URL
scheme of its own — every path it touches is either a local archive file
path or the caller-supplied destination directory, never a route this app
presents to a person.

## Localization

Not applicable: this concept declares no user-facing string literal. Its
error cases carry structured data — a digest string, a byte count, a
duration, a status code, or the extraction utility's raw diagnostic text —
rather than display text authored by this concept, and no operation returns
or logs a message meant to be read by a person.

## Accessibility Options

Not applicable: this is a non-visual archive-verification and extraction
utility with no rendered UI to respond to Reduce Motion, Increase Contrast,
or Differentiate Without Color.

## Feature Flags

Not applicable: this concept declares no feature-flag or configuration-flag
lookup — every call to verification or expansion runs the same fixed logic
unconditionally on every invocation.

## Analytics

Not applicable: this concept contains no event-emission or telemetry call
of any kind — verification and expansion return a value or fail directly to
the caller, with no recorded event.

## Privacy

- **Data collected**: This concept collects nothing of its own; it
  operates on whatever archive bytes, expected digest, signature, and
  public key the caller already holds, all of which originate from the
  registry response the caller fetched, not from a person using this
  device.
- **Storage**: Expansion writes the decompressed extension tree to the
  caller-supplied destination, which persists after the call returns by
  design — that is the point of expanding an archive. The scratch location
  used only to expand a signature archive far enough to read its signature
  entry is always removed before the call returns
  (**signature-scratch-cleanup**).
- **Transmission**: None. This concept performs no network I/O.
- **Retention**: This concept is stateless and retains nothing across calls
  (**stateless-namespace**); how long the expanded tree at the destination
  is kept is decided entirely by the caller once expansion returns.

## Logging

Subsystem: the host's logging subsystem | Category: this concept's own category

| Event | Level | Message |
|-------|-------|---------|
| — | — | Not emitted: this concept participates in the host's logging convention and declares a logger, but no operation calls it — every failure is communicated to the caller as a distinct error case instead of a log line. |

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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/VSIXArchive.swift` |

## Design Decisions

**Decision** (Swift/AppKit implementation, macOS): Shell out to
`/usr/bin/ditto -x -k` rather than a Swift or third-party zip library for
extraction.
**Rationale**: It is the platform's own unarchiver — the same one a Finder
double-click runs — and it already refuses the two ways a hostile archive
escapes its destination (a traversing relative or absolute entry name, and a
symlink written through), checked here against a purpose-built archive
rather than assumed. A pure-Swift unzip would have had to re-earn both, and
getting either subtly wrong is a directory traversal in a path that takes
third-party archives off the internet (doc comment).
**Approved**: pending

**Decision**: Bound expansion on two independent axes — a wall-clock
timeout and a decompressed-size byte ceiling — rather than one.
**Rationale**: A zip bomb is a compression ratio, not a duration: the
canonical ones write tens of gigabytes as fast as the disk accepts them and
then exit cleanly well inside a two-minute timeout, which is why the timeout
alone was previously (incorrectly) described as covering this case. The
ceiling and the timeout each catch an archive the other does not — one that
never finishes, and one that finishes by filling the disk.
**Approved**: pending

**Decision**: Set the expansion byte ceiling to 2 GiB, several times the
size of the largest real extension known to bundle a per-platform
language-server binary, rather than a tighter number closer to typical
extension size.
**Rationale**: Deflate reaches roughly 1000:1 compression on adversarial
input, so the 512 MB artifact download cap alone is license to decompress to
half a terabyte; 2 GiB is comfortably above any honest extension while
remaining small enough that reaching it leaves room on the volume to report
the failure.
**Approved**: pending

**Decision**: Name a fully verified result "registry attested" rather than
"verified," and treat a signature/key pair from the registry as proving the
bytes were not altered in transit — never as proving who published them.
**Rationale**: The public key arrives from a URL in the same JSON response
that named the archive and its digest; a registry serving altered bytes
signs them with a key of its own, publishes that key at that URL, and every
check in verification passes. There is no anchor to compare the key against
— Open VSX publishes no publisher key out of band, and this host has pinned
none — so the settings panel line this result feeds has to say "the
registry published," not "the publisher signed."
**Approved**: pending

**Decision**: Fail on a signature or key published alone, rather than
treating the pair as absent.
**Rationale**: Most of Open VSX is unsigned, so refusing every unsigned
extension would refuse the catalog — but one half of the pair present is a
different situation from neither being present: something *was* published,
and reporting that as an unsigned extension states the opposite of what
happened. The signature-incomplete error names which half is missing, which
is the fact a report against the registry needs.
**Approved**: pending

**Decision**: Check the digest before the signature, and always compute
the SHA-256 digest regardless of whether a digest to compare it against was
published.
**Rationale**: A digest mismatch is reported as a digest failure even when
a signature would otherwise verify, because a truncated or substituted
download is a different situation from a signing problem and should send
whoever reads the error looking at their network, not the publisher's key.
The hash is still computed when no digest was published because an install
record needs it to recognize these exact bytes later, but its presence must
not be read as "these bytes were checked" — hence the separate
"matched"/"not published" result rather than inferring a check from the
hash's presence.
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
| 1.0.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/registry/. |
