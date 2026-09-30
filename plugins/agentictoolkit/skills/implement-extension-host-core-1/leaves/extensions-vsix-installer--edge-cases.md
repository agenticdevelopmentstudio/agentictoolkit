<!-- leaf: implement-extension-host-core-1/extensions-vsix-installer--edge-cases · source: extension-host-core-extensions-vsix-installer.md -->

# VSIXInstaller

**Rules** (cite as `implement-extension-host-core-1/extensions-vsix-installer--edge-cases#<slug>`):

- `null-and-empty-input` MUST — An empty, absent, or unreadable package.json MUST be refused as manifestUnreadable or manifestMalformed before any …
- `boundary-values` MUST — A directory-name component that is safe but unusual — a pre-release version such as 1.0.0-beta.1+build.7 — MUST still …
- `malformed-input` MUST — identifier or version values that climb out of installDirectory with ../ sequences, that name an absolute path, or that …
- `error-states` MUST — A move into an existing destination that fails MUST attempt a rollback and MUST report, distinctly, whether that …
- `error-states-2` MUST — On the registry path, a network-level failure fetching the archive, the digest, the signature, or the public key MUST …
- `crash-power-loss-recovery` MUST — A power interruption between the two renames of moveIntoPlace MUST be recoverable by the next call to …

## Edge Cases

- **Null and empty input**: An empty, absent, or unreadable `package.json`
  MUST be refused as `manifestUnreadable` or `manifestMalformed` before any
  identity check runs (`manifest-unreadable`, `manifest-malformed`). An empty
  `manifest.identifier` or `manifest.version` MUST be refused by
  `identity-fields-validated`'s `ExtensionIdentityComponent.isSafe` empty-value
  rule, never reaching `directoryName`.
- **Boundary values**: A directory-name component that is safe but unusual —
  a pre-release version such as `1.0.0-beta.1+build.7` — MUST still install,
  distinguishing the identity guard's actual target (path-unsafe shapes) from
  merely unfamiliar ones (`identity-fields-validated`; test
  `prereleaseVersionStillInstalls`). An `installDirectory` reached through a
  `/private`-rooted path, where the directory exists but its intended child
  does not yet, MUST still install and MUST still refuse a climbing name from
  that same root (`destination-containment-double-checked`; tests
  `aPrivateRootedInstallDirectoryStillInstalls`,
  `aClimbingNameIsStillRefusedFromAPrivateRoot`).
- **Concurrent access**: The open question on `concurrent-install-ordering` —
  two `install(archive:...)` calls sharing one `installDirectory`, overlapping
  in time, have no documented ordering, mutual exclusion, or detection of the
  overlap; each independently runs its own recovery sweep, supersede scan, and
  `moveIntoPlace`, against the same directory tree.
- **Malformed input (hostile manifest fields)**: `identifier` or `version`
  values that climb out of `installDirectory` with `../` sequences, that name
  an absolute path, or that begin with a `.` (hiding the resulting directory
  from every scan that skips hidden files) MUST be refused by
  `identity-fields-validated` before any path is built, and the resulting
  destination's actual resolved location MUST also be refused by
  `destination-containment-double-checked` even if it somehow slipped past the
  first check — because `moveIntoPlace` finishes with a rename that resolves
  `..` in the kernel, past anything Foundation-level string checking would see
  (tests `hostileVersionIsRefused`, `hostileNameIsRefused`,
  `absolutePathIdentityIsRefused`, `hiddenDirectoryIdentityIsRefused`).
- **Error states (file system refuses partway through)**: A move into an
  existing destination that fails MUST attempt a rollback and MUST report,
  distinctly, whether that rollback itself succeeded or failed
  (`move-into-place-rollback`). A move into a destination with no existing
  copy that fails MUST leave nothing behind, hidden or otherwise
  (`move-into-place-atomicity`; test `aFailedFirstInstallLeavesNothing`). A
  superseded directory that cannot be removed MUST NOT fail an otherwise
  successful install (`supersede-non-fatal-removal`).
- **Error states (dependency unavailable)**: On the registry path, a
  network-level failure fetching the archive, the digest, the signature, or
  the public key MUST propagate as `OpenVSXClient`'s own thrown error type,
  before any verification or file-system step in this component begins. This component defines no retry, timeout, or cancellation of its
  own around that download; the effective behavior is whatever `client`
  provides (absence of any retry, timeout, or `Task` cancellation handling
  anywhere in `install(_:using:)`).
- **Crash / power-loss recovery**: A power interruption between the two
  renames of `moveIntoPlace` MUST be recoverable by the next call to
  `recoverInterruptedInstalls()` (which every `install(archive:...)` call runs
  first): the surviving aside is restored to its own name if the destination
  is empty, or discarded if the destination is already occupied
  (`recovery-sweep-scope`; tests `anInterruptedReplacementIsPutBack`,
  `aSupersededAsideIsDiscarded`, `installingRunsTheRecoverySweep`). An
  ordinary hidden entry that merely begins with a dot but does not match the
  aside naming convention MUST be left untouched by that same sweep
  (`recovery-non-aside-entries-untouched`; test
  `anUnrelatedHiddenEntryIsLeftAlone`).
- **Offline / disconnected state**: For `install(archive:...)`, there is no
  network dependency at all — the archive bytes are already in the caller's
  hand — so connectivity loss cannot occur mid-operation on that path. For
  `install(_:using:)`, connectivity lost during the archive, digest,
  signature, or key download surfaces as whatever error
  `OpenVSXClient`'s underlying `URLSession` produces, before this component
  writes anything to disk (same citation as the dependency-unavailable case
  above).
