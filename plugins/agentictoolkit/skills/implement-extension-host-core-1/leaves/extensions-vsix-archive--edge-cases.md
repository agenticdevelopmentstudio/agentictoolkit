<!-- leaf: implement-extension-host-core-1/extensions-vsix-archive--edge-cases · source: extension-host-core-extensions-vsix-archive.md -->

# VSIXArchive

**Rules** (cite as `implement-extension-host-core-1/extensions-vsix-archive--edge-cases#<slug>`):

- `null-and-empty-input` MUST — An archive of zero-length Data passed to verify MUST still be hashed successfully by sha256Hex(of:), which is a total …
- `boundary-values` MUST — A decompressed tree whose measured size is exactly equal to byteCeiling MUST NOT abort the run — only a running total …
- `error-states` MUST — When /usr/bin/ditto cannot be launched at all — for example if it were removed or unexecutable — …
- `malformed-input` MUST — An archive file that is not a valid zip MUST cause ditto to exit non-zero, reported as …
- `cancellation` MUST — verify and expand are synchronous, non-async functions with no Task and no cooperative cancellation check anywhere in …
- `timeout` MUST — An expand run that exceeds timeout MUST be terminated by CommandRunner, reported as …

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
